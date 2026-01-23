const grid = document.getElementById("grid");

const elems = {};

var importObject = {
    env: {
        consoleLog: function(ptr, len) {
          const memory = wasmInstance.exports.memory;
          console.log(new TextDecoder().decode(new Uint8Array(memory.buffer, ptr, len)));
        },
        setHtml: function(ptr, len) {
          const memory = wasmInstance.exports.memory;
          grid.textContent = new TextDecoder().decode(new Uint8Array(memory.buffer, ptr, len));
        },
        addElem: function(ptr, len, id, x, y, width, height) {
          const memory = wasmInstance.exports.memory;
          const elemName = new TextDecoder().decode(new Uint8Array(memory.buffer, ptr, len));
          if (elems[id] != undefined) {
            elems[id].remove();
          }

          const elem = document.createElement("div");

          const rect = grid.getBoundingClientRect();
          elem.style.position = "absolute";
          elem.style.top = (22 * y + rect.top) + "px";
          elem.style.left = (12 * x + rect.left) + "px";
          elem.style.width = (12 * width) + "px";
          elem.style.height = (22 * height) + "px";

          elem.className = elemName;

          grid.appendChild(elem);
          elems[id] = elem;
        },
    },
};

let wasmInstance;

WebAssembly.instantiateStreaming(fetch("zig-out/bin/xitlog.wasm"), importObject).then((result) => {
    wasmInstance = result.instance;
    result.instance.exports.start();
});
