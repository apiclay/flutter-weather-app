import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { createApp } from './server.mjs';

const SECRET = 'test-secret-do-not-use';

function weather(city = 'London') {
  return {
    location: {
      name: city,
      country: 'United Kingdom',
      localtime: '2026-11-09 23:15',
    },
    temperature: 7.1,
    humidity: 87,
    cloud: 10,
    wind: '5.1|ENE',
    uv: 0,
    air_quality: {
      'us-epa-index': 2,
    },
  };
}

function fakeResponse(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

async function setup(fetchImpl, clock = () => Date.now()) {
  const app = createApp({
    token: SECRET,
    fetchImpl,
    now: clock,
  });

  app.listen(0, '127.0.0.1');
  await once(app, 'listening');

  const address = app.address();
  const base = `http://127.0.0.1:${address.port}`;

  return {
    base,
    close: () => new Promise((resolve, reject) => {
      app.close(error => error ? reject(error) : resolve());
    }),
  };
}

test('GET /health reports healthy', async () => {
  const server = await setup(async () => {
    throw new Error('Upstream should not be called');
  });

  try {
    const res = await fetch(`${server.base}/health`);
    assert.equal(res.status, 200);
    assert.deepEqual(await res.json(), { status: 'ok' });
  } finally {
    await server.close();
  }
});

test('Maps city and token to upstream POST', async () => {
  let calls = 0;

  const server = await setup(async (url, options) => {
    calls++;
    assert.equal(
      url,
      'https://api.apiclay.com/v1/api/weather/current',
    );
    assert.equal(options.method, 'POST');
    assert.equal(options.headers.token, SECRET);
    assert.equal(
      options.headers['Content-Type'],
      'application/json',
    );
    assert.deepEqual(JSON.parse(options.body), {
      location: 'London',
    });
    assert.ok(options.signal);

    return fakeResponse(weather());
  });

  try {
    const res = await fetch(`${server.base}/weather?q=London`);
    const text = await res.text();
    const data = JSON.parse(text);

    assert.equal(res.status, 200);
    assert.equal(data.location, 'London');
    assert.equal(data.country, 'United Kingdom');
    assert.equal(data.temperature, 7.1);
    assert.equal(data.humidity, 87);
    assert.equal(data.cloud, 10);
    assert.equal(data.wind, '5.1|ENE');
    assert.equal(data.uv, 0);
    assert.equal(data.airQuality, 2);

    assert.equal(calls, 1);
    assert.equal(text.includes(SECRET), false);
    assert.equal('air_quality' in data, false);
    assert.equal('token' in data, false);
  } finally {
    await server.close();
  }
});

test('Rejects empty, duplicate and oversized queries', async () => {
  let calls = 0;
  const server = await setup(async () => {
    calls++;
    return fakeResponse(weather());
  });

  try {
    for (const path of [
      '/weather',
      '/weather?q=',
      '/weather?q=%20%20',
      '/weather?q=London&q=Tokyo',
      `/weather?q=${'x'.repeat(101)}`,
    ]) {
      const res = await fetch(server.base + path);
      assert.equal(res.status, 400, path);
    }

    assert.equal(calls, 0);
  } finally {
    await server.close();
  }
});

test('Sanitizes upstream failure and thrown errors', async () => {
  let calls = 0;
  const server = await setup(async () => {
    calls++;
    if (calls === 1) {
      return fakeResponse({
        secret: SECRET,
        error: 'Private provider details',
      }, 401);
    }
    throw new Error(`Internal upstream error: ${SECRET}`);
  });

  try {
    for (const city of ['London', 'Tokyo']) {
      const res = await fetch(
        `${server.base}/weather?q=${city}`,
      );
      const body = await res.text();

      assert.equal(res.status, 502);
      assert.equal(body.includes(SECRET), false);
      assert.equal(body.includes('Private provider'), false);
      assert.equal(body.includes('Internal upstream'), false);
    }
    assert.equal(calls, 2);
  } finally {
    await server.close();
  }
});

test('Caches by city for five minutes', async () => {
  let time = 1000000;
  let calls = 0;

  const server = await setup(async (_url, options) => {
    calls++;
    return fakeResponse(
      weather(JSON.parse(options.body).location),
    );
  }, () => time);

  try {
    const first = await fetch(
      `${server.base}/weather?q=London`,
    );
    assert.equal(first.status, 200);

    const second = await fetch(
      `${server.base}/weather?q=london`,
    );
    assert.equal(second.status, 200);
    assert.equal(calls, 1);

    time += 5 * 60 * 1000 + 1;

    const third = await fetch(
      `${server.base}/weather?q=London`,
    );
    assert.equal(third.status, 200);
    assert.equal(calls, 2);
  } finally {
    await server.close();
  }
});

test('Caps upstream attempts at 30 per hour', async () => {
  let calls = 0;
  let time = 1000000;

  const server = await setup(async (_url, options) => {
    calls++;
    return fakeResponse(
      weather(JSON.parse(options.body).location),
    );
  }, () => time);

  try {
    for (let i = 0; i < 30; i++) {
      const res = await fetch(
        `${server.base}/weather?q=City${i}`,
      );
      assert.equal(res.status, 200);
    }

    const blocked = await fetch(
      `${server.base}/weather?q=City30`,
    );
    assert.equal(blocked.status, 429);
    assert.equal(calls, 30);

    time += 60 * 60 * 1000 + 1;

    const allowed = await fetch(
      `${server.base}/weather?q=City30`,
    );
    assert.equal(allowed.status, 200);
    assert.equal(calls, 31);
  } finally {
    await server.close();
  }
});

test('Rejects malformed upstream weather data', async () => {
  const server = await setup(async () =>
    fakeResponse({ temperature: 7.1 }),
  );

  try {
    const res = await fetch(`${server.base}/weather?q=London`);
    assert.equal(res.status, 502);
    assert.deepEqual(await res.json(), {
      error: 'Weather provider returned invalid data.',
    });
  } finally {
    await server.close();
  }
});
