# dit4c-helper-listener-ngrok1

DIT4C routing connector based on the open source ngrok server.

There are three types of transport:
 * __TCP__ - random port on the server
 * __HTTP__ - vhost over HTTP
 * __HTTPS__ - vhost over HTTPS

# Extra steps for HTTPS

The HTTPS transport is the best choice for use with DIT4C, as it is the only
transport that provides encryption for public-side connections. As
[documented](ngrok_https), you will need a wildcard certificate to use `ngrokd`
in this mode.

Additionally, to use this listener with HTTPS, you will need to put a
reverse-proxy in front of ngrokd to add the `X-Forwarded-Proto` header. While
ngrok 2 adds this automatically, the open-source ngrok 1 server has only a
limited understanding of HTTP (enough to direct requests by vhost) and so is
incapable of doing this itself. The DIT4C auth helper needs this header so it
can generate URLs with the correct protocol scheme.

One way to do this is with [nghttpx][nghttpx], which has the added benefit of
providing HTTP/2.
```
                                       dit4c-helper-listener-ngrok1

                                                    +
                                           TLS/4443 |
                                                    v

                     +-----------+             +----------+
                     |           |             |          |
Browser  +---------> |  nghttpx  | +---------> |  ngrokd  |
          HTTPS/443  |           |  HTTPS/443  |          |
                     +-----------+             +----------+
```
ngrokd does not expect a reverse-proxy, and must be run on port 443. It is
possible to do this by having ngrokd only listen on the loopback interface,
however an easier deployment method is probably to use container network
namespacing.

[ngrok_https]: https://github.com/inconshreveable/ngrok/blob/master/docs/SELFHOSTING.md
[nghttpx]: https://nghttp2.org/documentation/nghttpx-howto.html
