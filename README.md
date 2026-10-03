This is a little static site generator for [xitlog](https://xit-vcs.github.io/xitlog/) written in Zig (requires version 0.16.0), a blog about [xit](https://github.com/xit-vcs/xit). It reads the blog posts out of `html/feed.xml` and renders them as html.

To re-generate the html files and view them in your browser:

```
zig build html
cd html
python -m http.server
```

As an experiment, you can also render the blog entirely client side with web assembly:

```
zig build wasm
cd wasm
python -m http.server
```

Lastly, you can also render the blog in your terminal for no reason in particular:

```
zig build run
```
