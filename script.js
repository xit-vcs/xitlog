const grid = document.getElementById("grid");

var importObject = {
    env: {
        _consoleLog: function(ptr, len) {
          const memory = wasmInstance.exports.memory;
          console.log(new TextDecoder().decode(new Uint8Array(memory.buffer, ptr, len)));
        },
        _setHtml: function(ptr, len) {
          const memory = wasmInstance.exports.memory;
          grid.innerHTML = new TextDecoder().decode(new Uint8Array(memory.buffer, ptr, len));
        },
    },
};

let wasmInstance;

WebAssembly.instantiateStreaming(fetch("zig-out/bin/xitlog.wasm"), importObject).then((result) => {
    wasmInstance = result.instance;
    wasmInstance.exports._start();
    document.addEventListener("keydown", (event) => {
        wasmInstance.exports._onKeyDown(event.keyCode);
    });

    function tick() {
        if (wasmInstance.exports._tick()) {
            requestAnimationFrame(tick);
        }
    }

    requestAnimationFrame(tick);
});
