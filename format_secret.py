import base64

file = './secrets/.env'

with open(file) as fp:
    line:str = fp.readline()
    while line:
        key, value = line.split(sep=" = ")
        encoded_value = base64.b64encode(value.encode('ascii'))

        print(f'{key}: >- \n  {str(encoded_value.decode())}')
        line:str = fp.readline()