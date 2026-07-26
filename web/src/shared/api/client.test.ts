import { describe, expect, it } from 'vitest';
import { apiErrorMessage, statusText } from './client';

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
});
