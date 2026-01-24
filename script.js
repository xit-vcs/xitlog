const grid = document.getElementById("grid");

var importObject = {
    env: {
        consoleLog: function(ptr, len) {
          const memory = wasmInstance.exports.memory;
          console.log(new TextDecoder().decode(new Uint8Array(memory.buffer, ptr, len)));
        },
        setHtml: function(ptr, len) {
          const memory = wasmInstance.exports.memory;
          grid.innerHTML = new TextDecoder().decode(new Uint8Array(memory.buffer, ptr, len));
        },
    },
};

let wasmInstance;

WebAssembly.instantiateStreaming(fetch("zig-out/bin/xitlog.wasm"), importObject).then((result) => {
    wasmInstance = result.instance;
    result.instance.exports.start();
});
