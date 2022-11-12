const fs = require("fs");

export function readJson(file: string) {
    if (fs.existsSync(file)) {
        let content = (`${fs.readFileSync(file)}` || "").trim() || "{}";

        return JSON.parse(content);
    }
    return {};
}

export function saveJson(file: string, obj: any) {
    if (!fs.existsSync(file)) {
        const filePath = file.replace(/\\/gi, "/");
        let folder = filePath.substring(0, filePath.lastIndexOf("/"));
        fs.mkdirSync(folder, { recursive: true });
    }
    fs.writeFileSync(file, JSON.stringify(obj, null, 4));
}
