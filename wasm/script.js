const grid = document.getElementById("grid");

let wasmInstance;
const decoder = new TextDecoder();
const encoder = new TextEncoder();
let currentHtml = "";

function readWasmString(ptr, len) {
    const memory = wasmInstance.exports.memory;
    return decoder.decode(new Uint8Array(memory.buffer, ptr, len));
}

function writeWasmString(value) {
    const bytes = encoder.encode(value);
    const ptr = wasmInstance.exports._alloc(bytes.length);
    if (ptr === 0) {
        throw new Error("wasm allocation failed");
    }
    new Uint8Array(wasmInstance.exports.memory.buffer, ptr, bytes.length).set(bytes);
    return { ptr, len: bytes.length };
}

function pageNameFromHref(href) {
    if (!href) return null;

    const url = new URL(href, window.location.href);
    if (url.origin !== window.location.origin) return null;
    if (!url.pathname.endsWith(".html")) return null;

    const filename = url.pathname.split("/").pop();
    if (!filename) return "index";
    return decodeURIComponent(filename.slice(0, -".html".length)) || "index";
}

function currentPageName() {
    if (!window.location.pathname.endsWith(".html")) return "index";
    const filename = window.location.pathname.split("/").pop();
    if (!filename) return "index";
    return decodeURIComponent(filename.slice(0, -".html".length)) || "index";
}

function navigate(pageName, pushHistory) {
    const arg = writeWasmString(pageName);
    try {
        return wasmInstance.exports._navigate(arg.ptr, arg.len, pushHistory);
    } finally {
        wasmInstance.exports._free(arg.ptr, arg.len);
    }
}

var importObject = {
    env: {
        _consoleLog: function(ptr, len) {
          console.log(readWasmString(ptr, len));
        },
        _setHtml: function(ptr, len) {
          const html = readWasmString(ptr, len);
          if (html !== currentHtml) {
            currentHtml = html;
            grid.innerHTML = html;
          }
        },
        _pushUrl: function(ptr, len) {
          const path = readWasmString(ptr, len);
          window.history.pushState({ pageName: pageNameFromHref(path) }, "", path);
        },
    },
};

WebAssembly.instantiateStreaming(fetch("xitlog.wasm"), importObject).then((result) => {
    wasmInstance = result.instance;
    wasmInstance.exports._start();

    const initialPageName = currentPageName();
    if (initialPageName !== "index") {
        navigate(initialPageName, false);
    }

    grid.addEventListener("click", (event) => {
        const target = event.target instanceof Element ? event.target : event.target.parentElement;
        const anchor = target ? target.closest("a") : null;
        if (!anchor || !grid.contains(anchor)) return;

        const pageName = pageNameFromHref(anchor.getAttribute("href"));
        if (pageName === null) return;

        event.preventDefault();
        navigate(pageName, true);
    });

    window.addEventListener("popstate", () => {
        navigate(currentPageName(), false);
    });

    document.addEventListener("keydown", (event) => {
        wasmInstance.exports._onKeyDown(event.keyCode);
        wasmInstance.exports._tick();
    });
});
