const fs = require("fs");
const path = require("path");

import { readJson, saveJson } from "./json";
import { publishPath } from "./env";

function readResource(network: string) {
    return readJson(path.join(publishPath, `${network}.json`));
}

function saveResource(network: string, obj: any) {
    saveJson(path.join(publishPath, `${network}.json`), obj);
}

export function readModuleResource(network: string, moduleName: string) {
    return readResource(network)[moduleName] || {};
}

export function saveModuleResource(network: string, moduleName: string, obj: any) {
    let resource = readResource(network) || {};
    resource[moduleName] = obj;
    saveResource(network, resource);
}
