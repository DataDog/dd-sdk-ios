#!/bin/zsh

curl -d '{"foo": "bar"}' -H "Content-Type: application/json" -X POST http://127.0.0.1:5000/rum/bar/
curl -d '{"foo": "bar"}' -H "Content-Type: application/json" -X POST http://127.0.0.1:5000/rum/bar/
curl -d '{"foo": "bar"}' -H "Content-Type: application/json" -X POST http://127.0.0.1:5000/rum/bar/
curl -d '{"foo": "bar"}' -H "Content-Type: application/json" -X POST http://127.0.0.1:5000/rum/bar/
curl -d '{"foo": "bar"}' -H "Content-Type: application/json" -X POST http://127.0.0.1:5000/rum/bar/

curl -d '{"foo": "bizz"}' -H "Content-Type: application/json" -X POST http://127.0.0.1:5000/foo/bizz/
curl -d '{"foo": "bizz"}' -H "Content-Type: application/json" -X POST http://127.0.0.1:5000/foo/bizz/
curl -d '{"foo": "bizz"}' -H "Content-Type: application/json" -X POST http://127.0.0.1:5000/foo/bizz/

curl -d '{"foo": "buzz/1"}' -H "Content-Type: application/json" -X POST http://127.0.0.1:5000/rum/buzz/1/
curl -d '{"foo": "buzz/1"}' -H "Content-Type: application/json" -X POST http://127.0.0.1:5000/rum/buzz/1/
curl -d '{"foo": "buzz/1"}' -H "Content-Type: application/json" -X POST http://127.0.0.1:5000/rum/buzz/1/
curl -d '{"foo": "buzz/1"}' -H "Content-Type: application/json" -X POST http://127.0.0.1:5000/rum/buzz/1/

curl -d '{"foo": "buzz/2"}' -H "Content-Type: application/json" -X POST http://127.0.0.1:5000/replay/buzz/2/
curl -d '{"foo": "buzz/2"}' -H "Content-Type: application/json" -X POST http://127.0.0.1:5000/replay/buzz/2/
curl -d '{"foo": "buzz/2"}' -H "Content-Type: application/json" -X POST http://127.0.0.1:5000/replay/buzz/2/
curl -d '{"foo": "buzz/2"}' -H "Content-Type: application/json" -X POST http://127.0.0.1:5000/replay/buzz/2/