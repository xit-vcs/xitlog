var memory = new WebAssembly.Memory({
    // See build.zig for reasoning
    initial: 2 /* pages */,
    maximum: 2 /* pages */,
});

let wasmMemory;

var importObject = {
    env: {
        consoleLog: function(ptr, len) {
          console.log(new TextDecoder().decode(new Uint8Array(wasmMemory.buffer, ptr, len)));
        },
        memory: memory,
    },
};

WebAssembly.instantiateStreaming(fetch("zig-out/bin/xitlog.wasm"), importObject).then((result) => {
    wasmMemory = new Uint8Array(memory.buffer);
    result.instance.exports.start();
});
