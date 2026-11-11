// Pinned Unicode 16.0 data; regeneration is optional and requires network.
import {writeFile,mkdir} from 'node:fs/promises';
const base='https://www.unicode.org/Public/16.0.0/ucd/';
async function get(path) {const response=await fetch(base+path); if(!response.ok) throw Error(`${path}: ${response.status}`); return response.text();}
const [gcb,emoji,derived,tests]=await Promise.all([get('auxiliary/GraphemeBreakProperty.txt'),get('emoji/emoji-data.txt'),get('DerivedCoreProperties.txt'),get('auxiliary/GraphemeBreakTest.txt')]);
function ranges(source,pick) {return source.split('\n').flatMap(line=>{const cells=line.split('#')[0].trim().split(';').map(s=>s.trim()); const property=pick(cells); if(!property || !/^[0-9A-F]+(?:\.\.[0-9A-F]+)?$/.test(cells[0])) return []; const [a,b=a]=cells[0].split('..').map(s=>parseInt(s,16)); return [{a,b,property}];}).sort((x,y)=>x.a-y.a);}
function table(name,rows) {return `const ${name} = [_]Range{\n${rows.map(r=>`    .{0x${r.a.toString(16)},0x${r.b.toString(16)},.${r.property.toLowerCase()}}`).join(',\n')}\n};\n`;}
const properties=ranges(gcb,c=>c[1]);
const pictographs=ranges(emoji,c=>c[1]==='Extended_Pictographic'?'pictographic':null);
const indic=ranges(derived,c=>c[1]==='InCB'?c[2]:null);
const kinds=[...new Set(['other','pictographic',...properties.map(r=>r.property.toLowerCase()),...indic.map(r=>r.property.toLowerCase())])];
const output=`//! Generated from Unicode 16.0.0 UCD; see tools/generate-graphemes.mjs.\n//! Unicode data license: https://www.unicode.org/license.txt\npub const Property=enum {${kinds.join(',')}};\nconst Range=struct{u21,u21,Property};\n${table('breaks',properties)}${table('emoji',pictographs)}${table('indic',indic)}
fn lookup(cp:u21,rows:[]const Range) Property {var lo:usize=0; var hi=rows.len; while(lo<hi){const mid=lo+(hi-lo)/2; const r=rows[mid]; if(cp<r[0]) hi=mid else if(cp>r[1]) lo=mid+1 else return r[2];} return .other;}
pub fn property(cp:u21) Property {return lookup(cp,&breaks);}
pub fn isPictographic(cp:u21) bool {return lookup(cp,&emoji)==.pictographic;}
pub fn conjunct(cp:u21) Property {return lookup(cp,&indic);}
`;
await mkdir(new URL('../modules/ui_core/unicode/',import.meta.url),{recursive:true});
await writeFile(new URL('../modules/ui_core/unicode/graphemes.zig',import.meta.url),output);
await writeFile(new URL('../modules/ui_core/unicode/GraphemeBreakTest.txt',import.meta.url),tests);
await writeFile(new URL('../modules/ui_core/unicode/LICENSE.txt',import.meta.url),await (await fetch('https://www.unicode.org/license.txt')).text());
console.log(`Generated ${properties.length} break ranges, ${indic.length} Indic ranges and official conformance fixtures`);
