mod_security SPOA Docker image
==============================

This repository builds a ready-to-use docker image with :
* mod_security 3.0.x
* spoa agent
* owasp rules


This image can be used with : 
- a standalone HAProxy
- HAProxy Kubernetes ingress controller


## How it works
HAProxy have a feature called [SPOE](https://www.haproxy.org/download/1.7/doc/SPOE.txt) 
that allows you to create extensions for it. SPOE can be used to mirror traffic,
and also to take decisions. 

This project is an agent for SPOE (SPOA), that receives transactions from HAProxy 
and validate them against ModSecurity rules.

## Usage
* Create / adapt modsecurity config files in rules/
* Build and launch the docker image.
* add filter SPOE to haproxy config (through configMap if K8s, in /etc/haproxy.cfg if standalone)


## Overrides
* mount modsecurity.conf to /rules/modsecurity.conf
* mount crs-setup.conf to /rules/coreruleset/crs-setup.conf
* add rules to any subfolder in /rules

## Configuration

### spoe-modsecurity.conf

```
[modsecurity]

spoe-agent modsecurity-agent
    messages check-request
    option var-prefix modsec
    timeout hello      100ms
    timeout idle       30s
    timeout processing 15ms
    use-backend spoe-modsecurity

spoe-message check-request
    args unique-id method path query req.ver req.hdrs_bin req.body_size req.body
    event on-frontend-http-request
```

### haproxy.cfg

First, declare modsecurity backend:
```
backend spoe-modsecurity
    mode tcp
    balance roundrobin
    timeout connect 5s
    timeout server  3m
    server modsec1 127.0.0.1:12345
```

on each frontend to filter, add this : 
```
frontend myapp:
    [...]
    filter spoe engine modsecurity config spoe-modsecurity.conf
    http-request deny if { var(txn.modsec.code) -m int gt 0 }
```

### modsecurity.conf (to be mounted as /rules/modsecurity.conf)
Source: https://raw.githubusercontent.com/SpiderLabs/ModSecurity/v3/master/modsecurity.conf-recommended

### crs-setup.conf (to be mounted as /rules/coreruleset/crs-setup.conf)
Source: https://raw.githubusercontent.com/coreruleset/coreruleset/v4.0/dev/crs-setup.conf.example


## Sources
* Inspired from https://github.com/rikatz/spoa-modsecurity-python (python implementation)
* spoa compilation from https://github.com/FireBurn/spoa-modsecurity