#!/usr/bin/perl

# main 

@contracts = (
    "Certification",
    "Committee",
    "ContractRegistry",
    "ContractRegistryListener",
    "Delegations",
    "Elections",
    "FeesAndBootstrapRewards",
    "FeesWallet",
    "GuardiansRegistration",
    "Lockable",
    "MigratableFeesWallet",
    "Protocol",
    "ProtocolWallet",
    "StakingContractHandler",
    "StakingRewards",
    "Subscriptions"
    );

$dir = "../multi/";
if (-e $dir and -d $dir) {
} else {
    mkdir $dir;
}
foreach $contract (@contracts) {
    $dir = "../multi/".$contract;
    if (-e $dir and -d $dir) {
    } else {
        mkdir $dir;
    }
    $str = "grep File: ../flat\/".$contract."\.sol";
    @files_raw = `$str`;
    foreach $file (@files_raw) {
        $file =~ /File: (.*.sol)/;
        $file_name_path = $1;
        $file_name_path =~ /\/([A-Za-z0-9]*.sol)/;
        $file_name = $1;
        if ($file_name_path =~ /openz.*(contracts.*sol)/) {
            $file_name_path = "openzeppelin/".$1;
#            $file_name_path = "node_modules\/\\".$file_name_path;
        }
        open($orig, '<', "../".$file_name_path);
        open($fixed, '>', "../multi/".$contract."/".$file_name);
        foreach $line (<$orig>) {
            if ($line =~ /import.*(\/[A-Za-z0-9]*.sol)/) {
                $line = "import \".".$1."\";\n";
            }
            print $fixed $line;
        }
        close($orig);
        close($fixed);
    }
}
