import * as fs from "fs";
import * as path from "path";

export type CompiledContracts = {[contractName: string]: any};

const EXCLUDE = ["IElections.json"];

function loadCompiledContracts(baseDir: string): CompiledContracts {
    const artifacts: CompiledContracts = {};
    for (const fname of fs.readdirSync(baseDir)) {
        if (EXCLUDE.includes(fname)) continue;

        const name = fname.replace('.json', '');
        const abi = JSON.parse(fs.readFileSync(baseDir + '/' + fname, {encoding:'utf8'}));
        artifacts[name] = abi;
    }
    return artifacts;
}

interface EventDefinition {
    name: string,
    signature: string,
    contractName: any
}

function listEventsDefinitions(contracts: CompiledContracts): EventDefinition[] {
    const defs: EventDefinition[] = [];

    for (const contractName in contracts) {
        const contract = contracts[contractName];
        const eventDefs: EventDefinition[] = contract.abi
            .filter(x => x.type == 'event')
            .map(e => ({
                contractName: contractName,
                name: e.name,
                signature: e.name + "(" + e.inputs.map(input => input.type).join(',') + ")"
            }));
        defs.push(...eventDefs);
    }

    return defs;
}

export const compiledContracts = loadCompiledContracts(path.join(__dirname, 'build', 'contracts'));
export const eventDefinitions = listEventsDefinitions(compiledContracts);
