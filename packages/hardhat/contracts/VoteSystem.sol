// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.11;
import "./Groth16VerifierProof.sol";
import "./Groth16VerifierUnreveal.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
 
contract VoteSystem is ERC721Enumerable {
    event Commit(
        uint256 indexed proposalId,
        address indexed committer,
        uint256 committementCounter
    );
    event VoteUnrevealed(
        uint256 indexed proposalId,
        uint256 optionIndex
    );
    event ProposalWinner(
        uint256 indexed proposalId,
        uint256 optionIndex
    );
    event ProposalCreated(uint256 indexed proposalId, uint256 phase1ExpirationDate, uint256 phase2ExpirationDate, uint256[] options);
    Groth16VerifierProof public verifierProof;
    Groth16VerifierUnreveal public verifierUnreveal;

    uint256     public maxSupply;
    uint256     public proposalCounter;
    uint256     public committementCounter;
    uint256     public ongoingPhase1Timer;
    uint256     public ongoingPhase2Timer;
    uint256[]   public ongoingOptions;
    uint256[]   public counterparts;

    mapping (address=>uint256)  public mintedFrom;
    mapping (uint256=>uint256)  public winnerByProposal;
    mapping (uint256=> mapping(uint256=>bool)) public nullifiers;
    mapping (uint256=>uint256)  public voteAggregates;

    constructor() ERC721("Urnae","URNAE"){
        verifierProof = new Groth16VerifierProof();
        verifierUnreveal = new Groth16VerifierUnreveal();
        maxSupply = 2e3;
    }

    function mint() public {
        require(totalSupply() < maxSupply, "Supply cap met!");
        require(mintedFrom[msg.sender] == 0, "Minted already, Oligarchy not allowed");
        mintedFrom[msg.sender]++;
        _safeMint(msg.sender, totalSupply()+1);
    }
    function aaa() public view returns (uint256){
        return block.timestamp;
    }
    function createProposal(
        uint256 phase1Timer,
        uint256 phase2Timer,
        uint[] memory options
        ) public {
        require(balanceOf(msg.sender) > 0, "Can't create a proposal");
        require(block.timestamp > ongoingPhase2Timer, "Proposal ongoing");
        require(phase1Timer < phase2Timer && phase1Timer > block.timestamp, "");
        ongoingPhase1Timer = phase1Timer;
        ongoingPhase2Timer = phase2Timer;
        winnerByProposal[proposalCounter] = checkVerdict(ongoingOptions); 
        emit ProposalWinner(proposalCounter, winnerByProposal[proposalCounter]);
        delete ongoingOptions;
        delete committementCounter;
        ongoingOptions = options;
        ++proposalCounter;
        emit ProposalCreated(proposalCounter, phase1Timer, phase2Timer, options);
    }

    function checkVerdict(uint256[] memory voteAllocation) public pure returns(uint256){
        //Draw and ballotage in v2 
        uint256 currentHighest;
        uint256 winnerIndex;
        for (uint i; i < voteAllocation.length; ){
            if (voteAllocation[i] > currentHighest) {
                currentHighest = voteAllocation[i];
                winnerIndex = i;
            }
            ++i;
        }
        return winnerIndex;
    }
   


    // PHASE 1 
    function sendCommitHash(uint256 commit) public {
        require(commit < 1e76 && commit > 1e75, "Invalid commit length");
        require(balanceOf(msg.sender) > 0, "Can't vote");
        require(block.timestamp < ongoingPhase1Timer, "Phase 1 has ended");
        ++committementCounter;
        counterparts.push(commit);
        emit Commit(proposalCounter, msg.sender, committementCounter);
    }

    function pickCounterparts(uint256[] memory counterpartsIndexes) public view returns (uint256){
        require(counterpartsIndexes.length >= 10, "Invalid length");
        uint256 counterpartChunkSum; 
        for (uint i; i < counterpartsIndexes.length;  ){
            
            counterpartChunkSum += counterparts[counterpartsIndexes[i]] / 1000;
            ++i; 
        }
        return counterpartChunkSum;
    }

    function proofUnreaveledVote(
    uint[2] calldata _pA,
    uint[2][2] calldata _pB,
    uint[2] calldata _pC,
    uint[3] calldata _pubSignals
    ) public {
        require(verifierProof.verifyProof(_pA, _pB, _pC, _pubSignals),"InvalidProof");
        require(_pubSignals[2] != 0, "No match in chunkSum");
        require(!nullifiers[proposalCounter][_pubSignals[1]], "Invalid nullifier");
        require(block.timestamp < ongoingPhase1Timer, "");
        nullifiers[proposalCounter][_pubSignals[1]] = true;
    }
    
    //Phase 2 Functions
    function proofRevaeledVote(
    uint[2] calldata _pA,
    uint[2][2] calldata _pB,
    uint[2] calldata _pC,
    uint[1] calldata _pubSignals
    ) public {
        require(verifierUnreveal.verifyProof(_pA, _pB, _pC, _pubSignals),"InvalidProof");
        require(block.timestamp < ongoingPhase1Timer, "Voting is over, unrevealed votes are null");
        voteAggregates[_pubSignals[0]] += 1;
        emit VoteUnrevealed(proposalCounter, _pubSignals[0]);
    }
}
