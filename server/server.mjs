import { createServer } from 'node:http';

const UPSTREAM = 'https://api.apiclay.com/v1/api/weather/current';
const CACHE_TTL = 5 * 60 * 1000;
const HOUR = 60 * 60 * 1000;
const MAX_CACHE = 100;
const MAX_CALLS = 30;

export function createApp({
  token,
  fetchImpl = globalThis.fetch,
  now = () => Date.now(),
} = {}) {
  const cache = new Map();
  const attempts = [];

  function send(res, status, data) {
    res.writeHead(status, {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
    });
    res.end(JSON.stringify(data));
  }

  return createServer(async (req, res) => {
    let url;

    try {
      url = new URL(req.url, 'http://localhost');
    } catch {
      send(res, 400, { error: 'Invalid request.' });
      return;
    }

    if (req.method === 'GET' && url.pathname === '/health') {
      send(res, 200, { status: 'ok' });
      return;
    }

    if (req.method !== 'GET' || url.pathname !== '/weather') {
      send(res, 404, { error: 'Not found.' });
      return;
    }

    const values = url.searchParams.getAll('q');
    if (values.length !== 1) {
      send(res, 400, { error: 'Provide one city name.' });
      return;
    }

    const city = values[0].trim();
    if (!city || city.length > 100 || /[\u0000-\u001F\u007F]/u.test(city)) {
      send(res, 400, {
        error: 'Enter a city name (1–100 characters).',
      });
      return;
    }

    if (typeof token !== 'string' || !token.trim()) {
      send(res, 503, { error: 'Weather service not configured.' });
      return;
    }

    const key = city.toLocaleLowerCase('en');
    const time = now();

    const cached = cache.get(key);
    if (cached && cached.expires > time) {
      // Refresh insertion order for LRU-style eviction.
      cache.delete(key);
      cache.set(key, cached);
      send(res, 200, cached.data);
      return;
    }
    if (cached) cache.delete(key);

    // Sliding one-hour window; count attempted upstream calls.
    while (attempts.length && attempts[0] <= time - HOUR) {
      attempts.shift();
    }

    if (attempts.length >= MAX_CALLS) {
      send(res, 429, {
        error: 'Weather request limit reached. Try later.',
      });
      return;
    }

    attempts.push(time);

    try {
      const upstream = await fetchImpl(UPSTREAM, {
        method: 'POST',
        headers: {
          token,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ location: city }),
        signal: AbortSignal.timeout(30000),
      });

      if (!upstream.ok) {
        send(res, 502, {
          error: 'Weather provider unavailable. Please retry.',
        });
        return;
      }

      const raw = await upstream.json();

      if (
        !raw ||
        typeof raw !== 'object' ||
        !raw.location ||
        typeof raw.location.name !== 'string' ||
        typeof raw.location.country !== 'string' ||
        typeof raw.location.localtime !== 'string' ||
        !Number.isFinite(raw.temperature) ||
        !Number.isFinite(raw.humidity) ||
        !Number.isFinite(raw.cloud) ||
        typeof raw.wind !== 'string' ||
        !Number.isFinite(raw.uv) ||
        !raw.air_quality ||
        !Number.isInteger(raw.air_quality['us-epa-index']) ||
        raw.air_quality['us-epa-index'] < 1 ||
        raw.air_quality['us-epa-index'] > 6
      ) {
        send(res, 502, {
          error: 'Weather provider returned invalid data.',
        });
        return;
      }

      const data = {
        location: raw.location.name,
        country: raw.location.country,
        localTime: raw.location.localtime,
        temperature: raw.temperature,
        humidity: raw.humidity,
        cloud: raw.cloud,
        wind: raw.wind,
        uv: raw.uv,
        airQuality: raw.air_quality['us-epa-index'],
      };

      cache.set(key, {
        data,
        expires: now() + CACHE_TTL,
      });

      while (cache.size > MAX_CACHE) {
        const oldest = cache.keys().next().value;
        cache.delete(oldest);
      }

      send(res, 200, data);
    } catch {
      // Never return upstream bodies, headers, tokens, or stack traces.
      send(res, 502, {
        error: 'Weather provider unavailable. Please retry.',
      });
    }
  });
}

const isMain = process.argv[1] &&
  import.meta.url === new URL(
    `file://${process.argv[1].replaceAll('\\', '/')}`,
  ).href;

if (isMain) {
  const token = process.env.APICLAY_TOKEN;
  const host = '127.0.0.1';
  const port = 8787;

  const app = createApp({ token });

  app.listen(port, host, () => {
    console.log(`Skycast backend listening on ${host}:${port}`);
  });
}
