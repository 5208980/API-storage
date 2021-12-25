import Express from 'express';
import path from 'path';
import multer from 'multer';    // Temporary store files on localdisk (so we can extract from user and upload to IPFS)
import { unlink } from 'fs/promises';   // Delete temporary files
import { Web3Storage, getFilesFromPath } from 'web3.storage';
import fs from "fs";
import solc from "solc";

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

    try {
        var tmpFile = req.file.filename;
    } catch (error) {
        res.end(JSON.stringify({ status: 404 }));
        return;
    }
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

app.get('/deploy', storage, async function(req, res) {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Content-Type', 'application/json');  // Create return content type (json)

    let compiled = compileSols(["Contract"]);
    console.log(compiled);

    res.end(JSON.stringify({ contract: compiled }));
});

app.get('/deploy/ehr', storage, async function(req, res) {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Content-Type', 'application/json');  // Create return content type (json)

    let compiled = compileSols(["EHR"]);
    console.log(compiled);

    res.end(JSON.stringify({ contract: compiled }));
});

app.listen(port, () => {
    console.log(`web3 app listening at http://localhost:${port}`)
})


function findImports(importPath) {
    try {
        return {
            contents: fs.readFileSync(`smart_contracts/${importPath}`, "utf8")
        };
    } catch (e) {
        return { error: e.message };
    }
}

function compileSols(solNames) {
    let sources = {};
    solNames.forEach((value, index, array) => {
        let sol_file = fs.readFileSync(`smart_contracts/${value}.sol`, "utf8");
        sources[value] = {
            content: sol_file
        };
    });
    let input = {
        language: "Solidity",
        sources: sources,
        settings: {
            outputSelection: {
                "*": {
                    "*": ["*"]
                }
            }
        }
    };
    let compiler_output = solc.compile(
        JSON.stringify(input), 
        { import: findImports }
    );
    let output = JSON.parse(compiler_output);
    return output;
}
