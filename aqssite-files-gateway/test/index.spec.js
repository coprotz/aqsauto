import { describe, expect, it } from 'vitest';
import worker from '../src';

describe('files gateway', () => {
  it('responds to health checks', async () => {
    const request = new Request('http://example.com/health');

    const response = await worker.fetch(request, {});

    expect(response.status).toBe(200);
    expect(await response.text()).toBe('OK');
    expect(response.headers.get('access-control-allow-origin')).toBe('*');
  });

  it('handles CORS preflight requests', async () => {
    const request = new Request('http://example.com/files/test.pdf', {
      method: 'OPTIONS',
      headers: {
        Origin: 'https://app.example.com',
        'Access-Control-Request-Method': 'GET',
      },
    });
    const response = await worker.fetch(request, {});

    expect(response.status).toBe(204);
    expect(response.headers.get('access-control-allow-origin')).toBe(
      'https://app.example.com',
    );
    expect(response.headers.get('access-control-allow-methods')).toContain('GET');
  });

  it('returns not found for unknown routes', async () => {
    const response = await worker.fetch(
      new Request('http://example.com/missing'),
      {},
    );

    expect(response.status).toBe(404);
    expect(await response.text()).toBe('Not Found');
  });

  it('requires an R2 binding for file reads', async () => {
    const response = await worker.fetch(
      new Request('http://example.com/files/test.pdf'),
      {},
    );

    expect(response.status).toBe(500);
    expect(await response.text()).toBe('R2 binding FILES not configured');
  });
});
