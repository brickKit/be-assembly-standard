#!/bin/bash
# Step 12, G7: one presigned GET signed for host.docker.internal:9000, fetched by a process on this machine (with
# `127.0.0.1 host.docker.internal` in /etc/hosts), a Docker container and a rootless Podman container (both with
# host.docker.internal:host-gateway), and once more on the host under the localhost alias (signature over the host:
# expected 403). Writes presign.out (the URL, credential and signature redacted afterwards) and fetch.out.
# Usage: run.sh   (from anywhere; needs the base resources up and boto3 in the conformance tools' environment)
set -eu
R=/home/zhijie/Desktop/github/be-assembly-standard; D=$(cd "$(dirname "$0")" && pwd)
envval() { grep "^$1=" "$R/.env" | cut -d= -f2- | tr -d "\"'"; }
export AK SK; AK=$(envval STORAGE_ACCESS_KEY); SK=$(envval STORAGE_SECRET_KEY)
(cd "$R/tools/be-acceptance/conformance" && uv run python - > "$D/presign.out") <<'EOF'
import os, hashlib, boto3
from botocore.config import Config
body = os.urandom(100 * 1024)
s3 = boto3.client("s3", endpoint_url="http://host.docker.internal:9000", region_name="us-east-1",
                  aws_access_key_id=os.environ["AK"], aws_secret_access_key=os.environ["SK"],
                  config=Config(signature_version="s3v4", s3={"addressing_style": "path"}))
s3.put_object(Bucket="be-acceptance", Key="g7/claim-check", Body=body)
print("sha256", hashlib.sha256(body).hexdigest())
print("url", s3.generate_presigned_url("get_object", Params={"Bucket": "be-acceptance", "Key": "g7/claim-check"},
                                       ExpiresIn=600))
EOF
URL=$(grep '^url ' "$D/presign.out" | cut -d' ' -f2); WANT=$(grep '^sha256 ' "$D/presign.out" | cut -d' ' -f2)
{
  echo "host (process on this machine): $(curl -s "$URL" | sha256sum | cut -c1-64) http=$(curl -s -o /dev/null -w '%{http_code}' "$URL")"
  echo "container (Docker, host-gateway): $(docker run --rm --add-host host.docker.internal:host-gateway alpine:3.22 wget -qO- "$URL" 2>/dev/null | sha256sum | cut -c1-64)"
  echo "host via localhost alias: http=$(curl -s -o /dev/null -w '%{http_code}' "${URL/host.docker.internal/localhost}")"
  echo "want: $WANT"
  echo "container (Podman rootless, host-gateway): $(podman run --rm --add-host host.docker.internal:host-gateway docker.io/library/alpine:3.22 wget -qO- "$URL" 2>/dev/null | sha256sum | cut -c1-64)"
} > "$D/fetch.out"
(cd "$R/tools/be-acceptance/conformance" && uv run python -c "
import os, boto3
boto3.client('s3', endpoint_url='http://localhost:9000', region_name='us-east-1', aws_access_key_id=os.environ['AK'],
             aws_secret_access_key=os.environ['SK']).delete_object(Bucket='be-acceptance', Key='g7/claim-check')")
sed -i 's/X-Amz-Credential=[^&]*/X-Amz-Credential=<redacted>/; s/X-Amz-Signature=[0-9a-f]*/X-Amz-Signature=<redacted>/' "$D/presign.out"
cat "$D/fetch.out"
