import boto3
import sys
from botocore.config import Config

def seed_route53_zone():
    print("Connecting to Moto Route53 endpoint...")
    
    # Configure client to communicate with your standalone Moto server
    r53_client = boto3.client(
        "route53",
        region_name="eu-west-2",
        endpoint_url="http://localhost:5001",
        aws_access_key_id="mock_key",
        aws_secret_access_key="mock_secret",
        config=Config(retries={'max_attempts': 0})
    )
    
    domain_name = "paymentstartupcde.com."
    
    try:
        # Check if Moto already has this hosted zone registered
        zones = r53_client.list_hosted_zones()["HostedZones"]
        if any(z["Name"] == domain_name for z in zones):
            print(f"Hosted Zone for '{domain_name}' already exists in Moto! Skipping seeding.")
            return
    except Exception as e:
        print(f"Could not connect to Moto Server or list zones: {e}")
        print("Please ensure 'moto_server -p 5001' is running and active.")
        sys.exit(1)

    print(f"Seeding Public Hosted Zone for: {domain_name}")
    response = r53_client.create_hosted_zone(
        Name=domain_name,
        CallerReference="moto_seed_init_001", 
        HostedZoneConfig={
            "Comment": "Local CDE Test Environment Seeding Ring",
            "PrivateZone": False
        }
    )
    
    zone_id = response["HostedZone"]["Id"].split("/")[-1]
    print(f"Successfully seeded! Hosted Zone ID: {zone_id}")

if __name__ == "__main__":
    seed_route53_zone()
