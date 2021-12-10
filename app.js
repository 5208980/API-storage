import Express from 'express';
import path from 'path';
import multer from 'multer';    // Temporary store files on localdisk (so we can extract from user and upload to IPFS)
import { unlink } from 'fs/promises';   // Delete temporary files
import { Web3Storage, getFilesFromPath } from 'web3.storage';

const app = Express();
var storage = multer({
    storage: multer.diskStorage({
    destination: function (req, file, cb) { 
        cb(null, 'uploads');
    },
    filename: function (req, file, cb) { 
        // console.log(file);
        cb(null, file.originalname + '-' + Date.now()); // give unique name
    }
    })
}).single('upload_documentation');

app.use(Express.json({ limit: '50mb' }));
app.use(Express.urlencoded({ extended: true, limit: '50mb' }));
app.use(Express.static(path.join(process.cwd(), 'static')));
const port = process.env.PORT || 8080;

app.get('/', function(req, res) {
    res.sendFile('index.html', { root: path.join(process.cwd(), '') });
});

app.post('/upload', storage, async function(req, res) {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Content-Type', 'application/json');  // Create return content type (json)

    // var tmpFile = req.file.filename;
    var tmpFile = req.file.filename;
    const token = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJkaWQ6ZXRocjoweEU3ZGMxZjdGMDlDNjJGZTk4NkMzODkzRDMzMGIwOTVFMjA1ZTJlYTUiLCJpc3MiOiJ3ZWIzLXN0b3JhZ2UiLCJpYXQiOjE2MzY4OTAxOTU5NTMsIm5hbWUiOiJNZWRpQ2hhaW4ifQ.rJiWMj-t6wRHHd3nez5DB6VuNNbgYjGvbPM2tclv0lg';

    const storage = new Web3Storage({ token });
    const pathFile = await getFilesFromPath(`./uploads/${tmpFile}`);

    console.log(`Uploading file to IPFS ...`);
    const cid = await storage.put(pathFile);
    console.log('Content added with CID:', cid);

    try {
        await unlink(`./uploads/${tmpFile}`);
        console.log(`success delete ./uploads/${tmpFile}`);
    } catch (error) {
        console.error('there was an error:', error.message);
    }
    res.end(JSON.stringify({ cid: cid }));
});

app.listen(port, () => {
    console.log(`web3 app listening at http://localhost:${port}`)
})