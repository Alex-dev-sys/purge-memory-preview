#!/usr/bin/env node
import { readFileSync, readdirSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const locales = ['en', 'zh-Hans', 'ru'];
const decode = literal => JSON.parse(literal);
const entry = /("(?:\\.|[^"\\])*")\s*=\s*("(?:\\.|[^"\\])*")\s*;/g;
const placeholders = value => [...value.matchAll(/%(?:\d+\$)?[-+#0 ]*\d*(?:\.\d+)?(?:hh|ll|h|l|q|z|t|j|L)?[@diuoxXfFeEgGcsp]/g)].map(m => m[0]).sort().join('|');
const tables = new Map();
for (const locale of locales) {
    const text = readFileSync(join(root, 'purge', `${locale}.lproj`, 'Memory.strings'), 'utf8');
    const table = new Map();
    for (const match of text.matchAll(entry)) {
        const key = decode(match[1]);
        const value = decode(match[2]);
        if (table.has(key) || !value.trim()) throw Error(`${locale}: duplicate or empty key: ${key}`);
        if (placeholders(key) !== placeholders(value)) throw Error(`${locale}: placeholder mismatch: ${key}`);
        table.set(key, value);
    }
    const remainder = text.replace(/\/\*[\s\S]*?\*\//g, '').replace(entry, '').trim();
    if (remainder) throw Error(`${locale}: unparsed .strings content`);
    tables.set(locale, table);
}
const english = tables.get('en');
for (const [locale, table] of tables) {
    if (table.size !== english.size || [...english.keys()].some(key => !table.has(key))) throw Error(`${locale}: Memory key sets differ`);
}
function swiftFiles(folder) {
    return readdirSync(folder, { withFileTypes: true }).flatMap(item => item.isDirectory()
        ? swiftFiles(join(folder, item.name)) : item.name.endsWith('.swift') ? [join(folder, item.name)] : []);
}
let used = 0;
for (const file of swiftFiles(join(root, 'purge'))) {
    const text = readFileSync(file, 'utf8');
    for (const match of text.matchAll(/memoryText\("((?:\\.|[^"\\])*)"\)/g)) {
        // Current Memory interpolations are Strings. Consume balanced nested parentheses.
        let body = match[1], key = '', i = 0;
        while (i < body.length) {
            if (body.slice(i, i + 2) === '\\(') {
                let depth = 1; i += 2;
                while (i < body.length && depth) { if (body[i] === '(') depth++; if (body[i] === ')') depth--; i++; }
                if (depth) throw Error(`${file}: incomplete interpolation`);
                key += '%@';
            } else { key += body[i++]; }
        }
        key = decode('"' + key + '"');
        if (!english.has(key)) throw Error(`${file}: missing Memory key: ${key}`);
        used++;
    }
}
console.log(`Memory localization passed: ${english.size} keys in EN/zh-Hans/RU; ${used} source references.`);
