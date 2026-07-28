import { afterEach, describe, expect, it, vi } from 'vitest';
import { ApiError, api, apiErrorMessage, statusText } from './client';

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('status wording', () => {
  it('describes offline state without relying on colour', () => {
    expect(statusText('offline')).toContain('no recent sensor report');
  });

  it('turns validation details into readable UI copy', () => {
    expect(
      apiErrorMessage(
        { detail: [{ loc: ['body', 'email'], msg: 'value is not a valid email address' }] },
        422,
      ),
    ).toBe('value is not a valid email address');
  });

  it('preserves the HTTP status on API failures', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({
        ok: false,
        status: 404,
        json: () => Promise.resolve({ detail: 'Tank not found' }),
      }),
    );

    await expect(api('/tanks/404')).rejects.toMatchObject({
      name: 'ApiError',
      message: 'Tank not found',
      status: 404,
    } satisfies Partial<ApiError>);
  });
});
