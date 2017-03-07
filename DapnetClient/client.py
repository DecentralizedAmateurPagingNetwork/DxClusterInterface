# -*- coding: utf-8 -*-

## Daniel Clerc <daniel@netzguerilla.net> 03/2017

import requests
import yaml

with open("../config.yml","r") as f:
    config = yaml.load(f.read()).get('dapnet')

API_URL = config.get('api_url')
USER = config.get('user')
PASS = config.get('pass')


class UpdateRubric:
    endpoint = "/news"
    
    def __init__(self, rubric_name):
        self.rubric_name = rubric_name

    def send(self, text):
        self.text = text
        payload = dict(text=self.text,
                       rubricName=self.rubric_name,
                       number=1,)

        r = requests.post(API_URL+self.endpoint, auth=(USER,PASS,), json=payload)
        # raise in case of a non 20X status code
        r.raise_for_status()

# example:
## i = UpdateRubric('dx-kw')
## i.send('Test Python-Client')
