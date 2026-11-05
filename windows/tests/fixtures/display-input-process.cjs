const fs = require('node:fs');
const { job, cancelFile, writeMarker } = JSON.parse(Buffer.from(process.argv[2], 'base64url').toString('utf8'));
if (job.identity) fs.writeFileSync(job.identity, String(process.pid));
if (job.kind === 'list') { process.send({ result: { status: 'listed', displays: [] } }); process.disconnect(); }
else if (job.target === 'hdmi') {
    const timer = setInterval(() => { if (fs.existsSync(cancelFile)) { clearInterval(timer); process.send({ result: { status: 'no-op', reading: { current: 5, maximum: 14 } } }); process.disconnect(); } }, 10);
} else { if (job.mapping?.typeC === 9) process.exit(1); if (job.mapping) fs.writeFileSync(writeMarker, '', { flag: 'wx' }); if (job.mapping?.typeC === 8) process.exit(1); if (job.mapping?.typeC >= 10) { const kind = job.mapping.typeC === 10 ? 'write-rejected' : job.mapping.typeC === 11 ? 'not-attempted' : 'uncertain'; process.send({ error: { kind, message: kind === 'write-rejected' ? 'rejected' : kind === 'not-attempted' ? 'cancelled' : 'unknown' } }); process.disconnect(); return; } setInterval(() => {}, 1000); }
