-include .env

# deps
update:; forge update
build  :; forge build
size  :; forge build --sizes

# storage inspection
inspect :; forge inspect ${contract} storage-layout --pretty

# specify which fork to use. set this in our .env
# if we want to test multiple forks in one go, remove this as an argument below
FORK_URL := ${ETH_RPC_URL} # BASE_RPC_URL, ETH_RPC_URL, ARBITRUM_RPC_URL

# if we want to run only matching tests, set that here
test := test_

# local tests without fork
test  :; forge test -vv --fork-url ${FORK_URL}
trace  :; forge test -vvv --fork-url ${FORK_URL}
gas  :; forge test --fork-url ${FORK_URL} --gas-report
test-contract  :; forge test -vv --match-contract $(contract) --fork-url ${FORK_URL}
test-contract-gas  :; forge test --gas-report --match-contract ${contract} --fork-url ${FORK_URL}
trace-contract  :; forge test -vvvv --match-contract $(contract) --fork-url ${FORK_URL}
test-test  :; forge test -vv --match-test $(test) --fork-url ${FORK_URL}
trace-test  :; forge test -vvvv --match-test $(test) --fork-url ${FORK_URL}

clean  :; forge clean
snapshot :; forge snapshot --fork-url ${FORK_URL}

# coverage
coverage :; forge coverage --fork-url ${FORK_URL} --report lcov
coverage-html :; forge coverage --fork-url ${FORK_URL} --report lcov && genhtml lcov.info -o coverage-report
