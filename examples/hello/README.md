# hello

The smallest Air app: four routes, no files, no JavaScript.

```
bend examples/hello/main.bend
curl localhost:8080/
curl localhost:8080/hello/world
curl 'localhost:8080/search?q=bend'
curl -d 'ping' localhost:8080/echo
```
