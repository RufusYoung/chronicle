import {execFileSync, spawnSync} from 'node:child_process';
import {writeFileSync, mkdirSync} from 'node:fs';
import {dirname, resolve} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {allowedPath, validateDocument, MAX_FILE_BYTES, Catalog} from './catalog.mjs';

const defaultRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export function buildSnapshot(root = defaultRoot, ref = 'HEAD') {
  const git = args => execFileSync('git', args, {cwd:root,maxBuffer:128*1024*1024});
  const commit = git(['rev-parse', '--verify', `${ref}^{commit}`]).toString().trim();
  const entries = git(['ls-tree','-r','-z',commit]).toString('utf8').split('\0').filter(Boolean).map(row => {
    const [head,path] = row.split('\t'); const [mode,type,oid] = head.split(' '); return {mode,type,oid,path};
  }).filter(e => e.type === 'blob' && e.mode === '100644' && allowedPath(e.path));
  const batch = spawnSync('git',['cat-file','--batch'],{cwd:root,input:entries.map(e=>e.oid).join('\n')+'\n',maxBuffer:128*1024*1024});
  if (batch.status !== 0 || batch.error) throw new Error('Cannot read committed snapshot');
  const documents = [], excludedOversize = []; let pos = 0;
  for (const entry of entries) {
    const end = batch.stdout.indexOf(10,pos);
    const size = Number(batch.stdout.subarray(pos,end).toString().split(' ')[2]);
    if (!Number.isSafeInteger(size) || size < 0) throw new Error('Invalid git blob frame');
    const body = batch.stdout.subarray(end+1,end+1+size); pos = end+1+size+1;
    if (size > MAX_FILE_BYTES) {excludedOversize.push(entry.path); continue;}
    const content = new TextDecoder('utf-8',{fatal:true}).decode(body);
    validateDocument(entry.path,content);
    documents.push({path:entry.path,content,sha256:createHash('sha256').update(content).digest('hex')});
  }
  const snapshot = {schema:1,commit,commitTime:git(['show','-s','--format=%cI',commit]).toString().trim(),publishedAt:new Date().toISOString(),repository:'RufusYoung/chronicle',excludedOversize,documents};
  new Catalog(snapshot);
  return snapshot;
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const output = resolve(process.argv[2] || resolve(defaultRoot,'work/mcp/snapshot.json'));
  const snapshot = buildSnapshot(defaultRoot, process.argv[3] || 'HEAD');
  mkdirSync(dirname(output),{recursive:true}); writeFileSync(output,JSON.stringify(snapshot));
  console.log(JSON.stringify({output,commit:snapshot.commit,documents:snapshot.documents.length,excludedOversize:snapshot.excludedOversize}));
}
