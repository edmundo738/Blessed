// ─────────────────────────────────────────────────────────────────────────────
// run.mjs — arranca o motor Godot (build web) em Node, sem browser.
//
// Porque existe: nesta máquina não há binário nativo do Godot e o CI do
// repositório precisa de correr o autoteste. O template web corre em Node com
// o display server "headless" do próprio motor — não é preciso WebGL nenhum.
//
// REGRA DE OURO: não chamar `emnapiInit`. Ele regista o motor como módulo
// Node-API e arranca uma SEGUNDA instância com argumentos vazios (sem
// --headless), que rebenta a pedir WebGL2. O motor arranca com `callMain`.
//
// Uso:
//   node tools/run.mjs --headless --quit-after 1500 -- selftest
//
// Variáveis de ambiente:
//   BLESSED_GEN  pasta gen/ do @ringozz/godot-web-wasm32 (default: ./node_modules/…)
//   BLESSED_PCK  caminho do .pck (default: ./blessed.pck ao lado deste ficheiro)
// ─────────────────────────────────────────────────────────────────────────────

import { readFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));

const GEN = process.env.BLESSED_GEN
	|| resolve(here, 'node_modules/@ringozz/godot-web-wasm32/gen');
const PCK = process.env.BLESSED_PCK || resolve(here, 'blessed.pck');

const args = process.argv.slice(2);
if (existsSync(PCK)) args.unshift('--main-pack', '/blessed.pck');

// ── ambiente mínimo ──────────────────────────────────────────────────────────
// O template web assume browser. Com --headless o motor não toca em WebGL, mas
// o áudio, o input e o canvas continuam a ser consultados no arranque.
function stubCanvas() {
	return {
		width: 1280, height: 720, clientWidth: 1280, clientHeight: 720,
		style: {}, dataset: {},
		addEventListener() {}, removeEventListener() {},
		setAttribute() {}, getAttribute() { return null; },
		focus() {}, blur() {},
		getBoundingClientRect() {
			return { left: 0, top: 0, right: 1280, bottom: 720, width: 1280, height: 720 };
		},
		getContext() { return null; }, // headless: nunca é preciso contexto gráfico
	};
}

const canvas = stubCanvas();

// Alguns destes nomes (navigator) sao propriedades so-de-leitura no Node 22.
function defineGlobal(name, value) {
	try {
		globalThis[name] = value;
	} catch {
		Object.defineProperty(globalThis, name, { value, configurable: true, writable: true });
	}
}

globalThis.window = globalThis;
globalThis.self = globalThis;
defineGlobal('navigator', {
	userAgent: 'blessed-headless', language: 'pt-PT', languages: ['pt-PT'],
	hardwareConcurrency: 4, maxTouchPoints: 0, platform: 'Linux',
});
globalThis.location = {
	href: 'http://localhost/', protocol: 'http:', host: 'localhost',
	hostname: 'localhost', search: '', hash: '', pathname: '/',
};
globalThis.screen = { width: 1280, height: 720, availWidth: 1280, availHeight: 720 };
globalThis.devicePixelRatio = 1;
globalThis.alert = (m) => { process.stderr.write(`[alert] ${m}\n`); };
globalThis.confirm = () => true;
globalThis.prompt = () => null;
globalThis.addEventListener = () => {};
globalThis.removeEventListener = () => {};
globalThis.requestAnimationFrame = (cb) => setTimeout(() => cb(performance.now()), 16);
globalThis.cancelAnimationFrame = (id) => clearTimeout(id);
globalThis.AudioContext = undefined;
globalThis.webkitAudioContext = undefined;
globalThis.localStorage = {
	_store: new Map(),
	getItem(k) { return this._store.has(k) ? this._store.get(k) : null; },
	setItem(k, v) { this._store.set(k, String(v)); },
	removeItem(k) { this._store.delete(k); },
	clear() { this._store.clear(); },
};
globalThis.document = {
	createElement(tag) {
		if (tag === 'canvas') return stubCanvas();
		return {
			style: {}, dataset: {}, children: [],
			appendChild() {}, removeChild() {}, setAttribute() {},
			addEventListener() {}, removeEventListener() {},
		};
	},
	getElementById() { return null; },
	querySelector() { return null; },
	addEventListener() {}, removeEventListener() {},
	body: { style: {}, appendChild() {}, removeChild() {} },
	documentElement: { style: {} },
	hidden: false,
	visibilityState: 'visible',
	hasFocus() { return true; },
	pointerLockElement: null,
};

// ── motor ────────────────────────────────────────────────────────────────────
const template = resolve(GEN, 'godot.web.template_release.wasm32.nothreads.js');
const wasm = resolve(GEN, 'godot.web.template_release.wasm32.nothreads.wasm');
const { default: createModule } = await import(`file://${template}`);

const wasmBinary = readFileSync(wasm);
const Module = await createModule({
	wasmBinary,
	arguments: args,
	canvas,
	locateFile: (p) => resolve(GEN, p),
	onAbort: (e) => { process.stderr.write(`[abort] ${e}\n`); },
});

Module.initConfig({ canvas, canvasResizePolicy: 2 });

if (existsSync(PCK)) {
	Module.copyToFS('/blessed.pck', readFileSync(PCK));
} else {
	process.stderr.write(`[run.mjs] sem .pck em ${PCK}\n`);
}

// O motor arranca aqui, com os NOSSOS argumentos. Sem emnapiInit.
Module.callMain(args);
