// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

contract zkuNFT is ERC721URIStorage {

    // safe convert uin256 to string functionality
    using Strings for uint256;

    // safe item incriment functionality
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    // construct token
    constructor() ERC721("zkuNFT", "zkuNFT") {}

    // mint new token to new account, returns tokenID
    function awardItem(address reciever, string memory tokenURI_)
        private
        returns (uint256)
    {
        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();
        _mint(reciever, newItemId);
        _setTokenURI(newItemId, tokenURI_);
        return newItemId;
    }

    // create a token URI with id and description field, returns URI
    function tokenURI(uint256 tokenId, string memory description_)
        private pure
        returns (string memory)
    {
        bytes memory dataURI = abi.encodePacked(
            '{',
                "name:", "My721Token #", tokenId.toString(), '"', ",",
                "description:", "721TokenDescription #", description_, '"',
            '}'
        );

        return string(
            abi.encodePacked(
                "data:application/json;base64,",
                Base64.encode(dataURI)
            )
        );
    }

    // this will create and send an NFT, hash its metadata, then return its hash
    function sendNFT(
        address reciever, 
        string memory tokenURI_, 
        uint256 tokenId, 
        string memory description
    ) 
        public payable
        returns(bytes32)
    {
        uint256 nftID = awardItem(reciever, tokenURI_);
        string memory URI = tokenURI(tokenId, description);
        return keccak256(abi.encodePacked(msg.sender, reciever, nftID, URI));
    }
}

interface IzkuNFT {
    function sendNFT(
        address reciever, 
        string memory tokenURI_, 
        uint256 tokenId, 
        string memory description
    ) 
    external payable
    returns(bytes32);
}

contract merkleTreeNFT is IzkuNFT {

    // tree implimented in array as followed
    /*
                        0
                1               2 
            3       4       5       6
    */

    // merkle tree with nodes, and transaction tracking variables
    bytes32[] merkleLeaves;
    // array index of merkle root
    uint256 merkleRootIndex = 0;
    uint256 powerOfTwo = 1;

    // depth of tree, counting from 0
    uint256 treeDepth = 0;

    // position in base array, also the transaction count
    uint256 offset = 0;
    uint256 transactionCount = 0;

    // store location of NFT smart contract, initialised to zero address
    address public zkuNFTAddress = address(0);

    /* 
     * require tree depth to be small, deploy NFT contract only on deployment of this contract, 
     * and initalise the merkle tree with some padded length, record length globally, where
     * tree size is enforced to be a power of two on contract creation 
     */
    constructor(uint256 treeHeight) {
        require(treeHeight < 10 && treeHeight > 1);
        zkuNFTAddress = address(new zkuNFT());
        merkleLeaves = new bytes32[](2**treeHeight - 1);
        for(uint i = 0; i < 2**treeHeight - 1; i++) {
            merkleLeaves[i] = 0x0000000000000000000000000000000000000000000000000000000000000000;
        }
        // disregard row 0
        treeDepth = treeHeight - 1;
        merkleRootIndex = 2**treeHeight - 1;
    }

    /*
     * get the sendNFT function from the NFT contract, send the NFT, and then add the NFT metadata
     * hash to the merkle tree
     */
    function sendNFT(
        address reciever,
        string memory tokenURI_,
        uint256 tokenId,
        string memory description
    ) 
        public payable
        override
        returns(bytes32)
    {
        bytes32 metadata = IzkuNFT(zkuNFTAddress).sendNFT(reciever, tokenURI_, tokenId, description);
        merkleAddNFT(metadata);
        return metadata;
    }

    // function to expose the transaction data
    function getMerkleLeaves() 
        public view
        returns(bytes32[] memory)
    {
        return merkleLeaves;
    }

    // hash two bytes32, return result
    function hash(bytes32 hash_0, bytes32 hash_1)
        private pure
        returns(bytes32)
    {
        return keccak256(abi.encodePacked(hash_0, hash_1));
    }

    // update the merkle tree and transaction tracking data 
    function merkleAddNFT(bytes32 metadata)
        private
    {
        transactionCount++;
        calculateNewRootIndex();

        // handle base case, single element add to array
        if(transactionCount == 1){
            merkleRootIndex = 2**treeDepth - 1;
            merkleLeaves[2**treeDepth - 1 + offset] = metadata;
        }

        // handle simple two element merkle tree
        else if(transactionCount == 2) {
            merkleRootIndex = 2**(treeDepth - 1) - 1;
            merkleLeaves[2**treeDepth - 1 + offset] = metadata;
            uint256 parent = ((2**treeDepth - 1 + offset) - 1) / 2;
            bytes32 childLeft = merkleLeaves[2 * parent + 1];
            bytes32 childRight = merkleLeaves[2 * parent + 2];
            merkleLeaves[parent] = hash(childLeft, childRight);
        }
        
        // generalise the above
        else{
            // add the new transaction
            merkleLeaves[2**treeDepth - 1 + offset] = metadata;
            // keep track of parent
            uint256 parent = 2**treeDepth - 1 + offset;
            // count down layers, check to see if there are dummy leaves, add new leaves depending on this
            while(parent >= 1) {
                parent = (parent - 1) / 2;
                bytes32 childLeft = merkleLeaves[2 * parent + 1];
                bytes32 childRight = merkleLeaves[2 * parent + 2];
                if(childRight == 0x0000000000000000000000000000000000000000000000000000000000000000){
                    merkleLeaves[parent] = hash(childLeft, childLeft);
                } 
                else {
                    merkleLeaves[parent] = hash(childLeft, childRight);
                }
            }
        }

        // each new nft increases offset of base array by one
        offset++;
    }

    function getMerkleRootIndex()
    public view returns(uint256){return merkleRootIndex;}

    // get the current merkle root index
    function calculateNewRootIndex() 
        private 
    {
        if(transactionCount == powerOfTwo && merkleRootIndex >= 0){
            powerOfTwo = powerOfTwo * 2;
            merkleRootIndex = (merkleRootIndex - 1) / 2;
        }
    }
}
