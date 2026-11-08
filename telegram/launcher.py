"""Headless official TG WS Proxy, configured by the native host over stdin."""
import json, sys, signal, os
if __name__ == '__main__':
    os.umask(0o077)
    if '--self-test' in sys.argv:
        from proxy._aes import Cipher,algorithms,modes
        from proxy.tg_ws_proxy import _try_handshake
        import httpx,certifi
        from utils.logging_setup import build_log_handler
        assert os.path.isfile(certifi.where())
        print('TG WS Proxy core and TLS certificates: OK')
        raise SystemExit(0)
    config = json.loads(sys.stdin.buffer.readline(8193))
    port = int(config['port']); secret = config['secret']
    if not 1024 <= port <= 65535 or len(secret) != 32 or any(c not in '0123456789abcdef' for c in secret):
        raise SystemExit('Invalid local proxy configuration')
    # The OS-visible argv contains no secret. Disable pinned DC redirects;
    # let the upstream core select the actual Telegram datacenter.
    sys.argv = ['tgws','--host','127.0.0.1','--port',str(port),'--secret',secret,'--dc-ip',
                '--log-file',config['log'],'--log-max-mb','2','--log-backups','1']
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    from proxy.tg_ws_proxy import main
    main()
