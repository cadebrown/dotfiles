import {createServer} from 'node:http';
import {readFile} from 'node:fs/promises';
const html = await readFile(new URL('./index.html', import.meta.url));
const port = Number(process.env.PORT || 4317);
createServer((request, response) => {
  if (request.url === '/' || request.url === '/index.html') {
    response.writeHead(200, {'content-type': 'text/html; charset=utf-8'}).end(html);
  } else {
    response.writeHead(404).end('Not found');
  }
}).listen(port, '127.0.0.1', () => process.stdout.write(`Interaction lab: http://127.0.0.1:${port}\n`));
