import yaml
from yaml.loader import SafeLoader

file = './secrets/bd-ml-prd.yaml'
# Open the file and load the file
with open(file) as f:
    data:dict = yaml.load(f, Loader=SafeLoader)

metadata:dict = data.get('metadata')
secret_name = metadata.get('name')
secrets:dict = data.get('data')

env = []
for key in secrets.keys():
    base = {
        'name': key,
        'valueFrom':{
            'secretKeyRef': {
                'name': secret_name,
                'key': key
            }
        }
    }
    env.append(base)
print(yaml.dump({'env':env}))