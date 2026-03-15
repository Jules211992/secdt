'use strict';

const { WorkloadModuleBase } = require('@hyperledger/caliper-core');
const crypto = require('crypto');

class RegisterStateWorkload extends WorkloadModuleBase {
    constructor() {
        super();
        this.txIndex = 0;
        this.runTag = 'run-' + Date.now() + '-' + Math.floor(Math.random() * 1000000);
    }

    async submitTransaction() {
        this.txIndex++;

        const roundIndex = this.roundIndex !== undefined ? this.roundIndex : 0;
        const workerIndex = this.workerIndex !== undefined ? this.workerIndex : 0;

        const uniqueBase = `${this.runTag}-r${roundIndex}-w${workerIndex}-tx${this.txIndex}`;

        const machineId = `machine-caliper-${uniqueBase}`;
        const cid = `QmCaliperCID-${uniqueBase}`;
        const healthScore = (80 + (this.txIndex % 20) + 0.5).toFixed(1);
        const cycle = (100 + this.txIndex).toString();
        const sessionId = `session-${uniqueBase}`;

        const hash = crypto
            .createHash('sha256')
            .update(`${machineId}|${cid}|${healthScore}|${cycle}|${sessionId}|${uniqueBase}`)
            .digest('hex');

        const request = {
            contractId: 'secdt',
            contractFunction: 'RegisterState',
            invokerIdentity: 'admin',
            contractArguments: [
                machineId,
                cid,
                healthScore,
                cycle,
                sessionId,
                hash
            ],
            readOnly: false
        };

        await this.sutAdapter.sendRequests(request);
    }
}

function createWorkloadModule() {
    return new RegisterStateWorkload();
}

module.exports.createWorkloadModule = createWorkloadModule;
