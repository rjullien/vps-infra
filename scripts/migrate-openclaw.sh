scp -P 22222 openclaw.tar.gz node@vps:/tmp
kubectl exec -it -n openclaw $(kubectl -n openclaw get pods | grep openclaw | cut -f1 -d ' ') -- bash
cp -a /openclaw/data/. /home/node/.openclaw/
cp -a /openclaw/ssh/. /home/node/.ssh
cp -a /openclaw/config/. /home/node/.config/