import {readFileSync, existsSync, writeFileSync} from 'node:fs';
import {dirname,join} from 'node:path';
import {runCheck} from './check.mjs';

const configPath = process.argv[2] || 'C:/code/game/chronicle-private/mcp/connection.json';
const config = JSON.parse(readFileSync(configPath,'utf8'));
const clientPath = join(dirname(configPath),'verification-client.json');
const client = existsSync(clientPath) ? JSON.parse(readFileSync(clientPath,'utf8')) : undefined;
const result = await runCheck(config.baseUrl,config.password,client);
writeFileSync(clientPath,JSON.stringify(result.client),{mode:0o600});
delete result.client;
console.log(JSON.stringify(result,null,2));
