import { spawn, ChildProcess } from 'child_process';
import { ETHEREUM_URL } from '../eth';
import fetch from 'node-fetch';
import { retry } from 'ts-retry-promise';

export const ganacheDriver = {
    process: null as ChildProcess | null,
    async startGanache() {
        if (ganacheDriver.process) {
            throw new Error(`ganache-cli process already running! PID=${ganacheDriver.process.pid}`);
        }
        try {
            const process = spawn(
                'ganache-cli',
                [
                    '-p',
                    '7545',
                    '-i',
                    '5777',
                    '-a',
                    '100',
                    '-m',
                    'vanish junk genuine web seminar cook absurd royal ability series taste method identify elevator liquid'
                ],
                { stdio: 'pipe' }
            );
            ganacheDriver.process = process;
            await retry(
                () =>
                    fetch(ETHEREUM_URL, {
                        method: 'POST',
                        body: JSON.stringify({ jsonrpc: '2.0', method: 'web3_clientVersion', params: [], id: 67 })
                    }),
                { retries: 10, delay: 300 }
            );
        } catch(e) {
            console.log('Ganache startup failure');
            await ganacheDriver.stopGanache();
            throw e;
        }
        console.log('Ganache is up');
    },
    async stopGanache() {
        if (ganacheDriver.process) {
            try {
                console.log('Ganache goes down');
                ganacheDriver.process.kill('SIGINT');
                await new Promise(res => ganacheDriver.process!.on('exit', res));
            } catch(e) {
                console.log('Ganache shutdown failure', e);
            } finally {
                ganacheDriver.process = null;
            }
        }
    }
};