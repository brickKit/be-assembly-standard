"""RustFS: a conditional create (If-None-Match: *) on an object-lock bucket, and whether an object-lock put needs
Content-MD5 (AWS requires an integrity header for object-lock puts)."""
import base64, datetime, hashlib, os, uuid
import boto3
from botocore.exceptions import ClientError
s3 = boto3.client("s3", endpoint_url=os.environ["S3_URL"], aws_access_key_id=os.environ["S3_KEY"],
                  aws_secret_access_key=os.environ["S3_SECRET"], region_name="us-east-1")
b = "condput-probe-" + uuid.uuid4().hex[:8]
s3.create_bucket(Bucket=b, ObjectLockEnabledForBucket=True)
until = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(minutes=2)
def put(label, **kw):
    try:
        r = s3.put_object(Bucket=b, Key="k", Body=b"v", ObjectLockMode="COMPLIANCE", ObjectLockRetainUntilDate=until, **kw)
        print(label, "ok", r["ResponseMetadata"]["HTTPStatusCode"])
    except ClientError as e:
        print(label, "refused", e.response["Error"].get("Code"), e.response["ResponseMetadata"]["HTTPStatusCode"])
md5 = base64.b64encode(hashlib.md5(b"v").digest()).decode()
put("first create with If-None-Match", IfNoneMatch="*", ContentMD5=md5)
put("second create with If-None-Match (must be refused)", IfNoneMatch="*", ContentMD5=md5)
print("versions of k:", len(s3.list_object_versions(Bucket=b, Prefix="k").get("Versions", [])))
print("bucket", b, "locked until", until.isoformat())
