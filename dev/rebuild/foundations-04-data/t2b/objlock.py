"""Does the S3 store keep an object-locked object unchangeable? A bucket with object lock, an object with a
retention, then attempts to delete that version and to shorten the retention (both must be refused)."""
import datetime, os, sys, uuid
import boto3
from botocore.exceptions import ClientError
s3 = boto3.client("s3", endpoint_url=os.environ["S3_URL"], aws_access_key_id=os.environ["S3_KEY"],
                  aws_secret_access_key=os.environ["S3_SECRET"], region_name="us-east-1")
b = "objlock-probe-" + uuid.uuid4().hex[:8]
def step(name, f):
    try:
        r = f(); print(f"{name}: ok", (r or {}).get("ResponseMetadata", {}).get("HTTPStatusCode", ""))
        return r
    except ClientError as e:
        print(f"{name}: refused {e.response['Error'].get('Code')}")
step("create bucket with object lock", lambda: s3.create_bucket(Bucket=b, ObjectLockEnabledForBucket=True))
until = datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(minutes=10)
r = step("put with COMPLIANCE retention 10 min", lambda: s3.put_object(Bucket=b, Key="k", Body=b"v1",
         ObjectLockMode="COMPLIANCE", ObjectLockRetainUntilDate=until))
v = (r or {}).get("VersionId")
print("version id:", v)
step("get retention", lambda: print("  ", s3.get_object_retention(Bucket=b, Key="k", VersionId=v)["Retention"]))
step("delete that version (must be refused)", lambda: s3.delete_object(Bucket=b, Key="k", VersionId=v))
step("shorten retention (must be refused)", lambda: s3.put_object_retention(Bucket=b, Key="k", VersionId=v,
     Retention={"Mode": "COMPLIANCE", "RetainUntilDate": datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(seconds=5)}))
step("bypass governance on a compliance object (must be refused)", lambda: s3.delete_object(Bucket=b, Key="k", VersionId=v, BypassGovernanceRetention=True))
print("object still readable:", s3.get_object(Bucket=b, Key="k", VersionId=v)["Body"].read())
print("bucket", b, "left in place (its object is locked for 10 min)")
