// SPDX-License-Identifier: MIT
pragma solidity =0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./Traits.sol";

contract TraitsMint is Ownable {
    address private _signerAddress;
    bool public isClaimingEnabled;
    mapping(address => bool) private _claimers;
    mapping(address => mapping(uint256 => uint256)) private _nonces;

    address private immutable _traitsContract;

    constructor(address traitsContract) {
        _traitsContract = traitsContract;
    }

    modifier canClaim() {
        require(isClaimingEnabled, "Claiming is disabled");
        _;
    }

    function claimMultiple(uint256[] calldata ids, uint256[] calldata amounts, address account, uint256[] calldata nonces, uint256 deadlineTimestamp, bytes32 signatureR, bytes32 signatureVS) external canClaim {
        require(msg.sender == account || _claimers[msg.sender], "Not allowed to claim");
        require(deadlineTimestamp == 0 || deadlineTimestamp > block.timestamp, "Deadline to claim has passed");

        {
            bytes32 hash = keccak256(abi.encode(ids, amounts, account, nonces, deadlineTimestamp));
            require(_signerAddress == ECDSA.recover(hash,  signatureR,  signatureVS), "Invalid signature");
        }

        unchecked {
            uint256 length = nonces.length;
            require(length > 0, "nonces array is empty");
            uint256 nonceIndex = nonces[0];
            uint256 mask = 1 << (nonceIndex & 0xff);
            nonceIndex >>= 8;            
            for (uint256 i=1; i<length; ++i) {
                uint256 nonce = nonces[i];
                uint256 i_nonceIndex = nonce >> 8;
                if (i_nonceIndex != nonceIndex) {
                    uint256 noncePacked = _nonces[account][nonceIndex];
                    require((noncePacked & mask) == 0, "Already claimed");
                    _nonces[account][nonceIndex] = noncePacked | mask;

                    nonceIndex = i_nonceIndex;
                    mask = 0;
                }
                mask |= (1 << (nonce & 0xff));
            }
            
            {
                uint256 noncePacked = _nonces[account][nonceIndex];
                require((noncePacked & mask) == 0, "Already claimed");
                _nonces[account][nonceIndex] = noncePacked | mask;
            }
        }
        
        Traits(_traitsContract).mintBatch(account, ids, amounts);
    }

    function claim(uint256[] calldata ids, uint256[] calldata amounts, address account, uint256 nonce, uint256 deadlineTimestamp, bytes32 signatureR, bytes32 signatureVS) external canClaim {
        require(msg.sender == account || _claimers[msg.sender], "Not allowed to claim");
        require(deadlineTimestamp == 0 || deadlineTimestamp > block.timestamp, "Deadline to claim has passed");

        {
            bytes32 hash = keccak256(abi.encode(ids, amounts, account, nonce, deadlineTimestamp));
            require(_signerAddress == ECDSA.recover(hash,  signatureR,  signatureVS), "Invalid signature");
        }
        
        uint256 nonceIndex = nonce >> 8;
        uint256 noncePacked = _nonces[account][nonceIndex];
        uint256 noncePackedNew = noncePacked | (1 << (nonce & 0xff));
        require(noncePacked != noncePackedNew, "Already claimed");
        _nonces[account][nonceIndex] = noncePackedNew;
        
        Traits(_traitsContract).mintBatch(account, ids, amounts);
    }


    function isNonceClaimed(address account, uint256 nonce) external view returns(bool) {
        uint256 nonceIndex = nonce >> 8;
        return (_nonces[account][nonceIndex] & (1 << (nonce & 0xff))) != 0;
    }

    function areNoncesClaimed(address account, uint256[] calldata nonces) external view returns(bool[] memory) {
        uint256 length = nonces.length;
        bool[] memory results = new bool[](length);
        unchecked {
            for (uint256 i=0; i<length; ++i) {
                uint256 nonce = nonces[i];
                uint256 nonceIndex = nonce >> 8;
                results[i] = (_nonces[account][nonceIndex] & (1 << (nonce & 0xff))) != 0;
            }
        }
        return results;
    }



    function setSignerAddress(address signerAddress) external onlyOwner {
        _signerAddress = signerAddress;
    }

    function setClaimer(address claimer, bool enabled) external onlyOwner {
        require(claimer != address(0), "Invalid claimer");
        _claimers[claimer] = enabled;
    }

    function setClaimingEnabled(bool enabled) external onlyOwner {
        isClaimingEnabled = enabled;
    }
}
