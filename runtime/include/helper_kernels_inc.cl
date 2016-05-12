
void memcpy ( void *dst, const void *src, size_t size)
{
    size_t i;
    uchar *d = dst;
    const uchar *s = src;
    for (i = 0; i < size; ++i) {
        d[i] = s[i];
    }
}
