#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>

int __fprintf_chk(FILE *stream, int flag, const char *format, ...)
{
    int ret;
    va_list ap;

    (void)flag;
    va_start(ap, format);
    ret = vfprintf(stream, format, ap);
    va_end(ap);
    return ret;
}

int __vsnprintf_chk(char *str, size_t maxlen, int flag, size_t slen,
                    const char *format, va_list ap)
{
    (void)flag;
    (void)slen;
    return vsnprintf(str, maxlen, format, ap);
}
