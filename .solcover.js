fs = require("fs-extra");

module.exports = {
    providerOptions: {
        mnemonic: "vanish junk genuine web seminar cook absurd royal ability series taste method identify elevator liquid",
        gasPrice: "0x1",
        gasLimit: "0xFFFFFFFF",
        allowUnlimitedContractSize: true,
        total_accounts: 200,
        default_balance_ether: 100,
        port: 7545
    },
    port: 7545,
    onCompileComplete: () => {
        fs.copySync(__dirname + '/.coverage_artifacts', __dirname + '/build');
    },
    mocha: {
        grep: '[skip-coverage]',
        invert: true
    }
};
