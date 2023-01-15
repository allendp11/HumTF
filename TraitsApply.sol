// SPDX-License-Identifier: MIT
pragma solidity =0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./Traits.sol";

contract TraitsApply is Ownable {
    bool private _isEnabled;
    uint48 private _deadlineTimestamp;
    uint48 private _startBlockNumber;

    address private immutable _traitsContract;
    address private immutable _tokenContract;

    /**
     * @dev Emitted when `owner` applies `traitIds` to NFT `tokenId`.
     */
    event ApplyTraits(address indexed owner, uint256 indexed tokenId, uint256[] traitIds);

    /**
     * @dev Emitted when an apply period is set or updated.
     */
    event ApplyPeriod(uint256 startBlockNumber, uint256 deadlineTimestamp);

    constructor(address traitsContract, address tokenContract) {
        _traitsContract = traitsContract;
        _tokenContract = tokenContract;
    }

    modifier canApply() {
        require(_isEnabled, "Applying traits is disabled");
        require(block.timestamp <= _deadlineTimestamp, "Deadline for applying traits has passed");
        _;
    }

    
    function applyTraitsToTokens(uint256[] calldata traitIds, uint256[] calldata tokenIds) external canApply {
        uint length = traitIds.length;
        require(length > 0 && length == tokenIds.length, "Invalid array lengths");

        // create a temp array for the ApplyTraits event logs
        uint256[] memory traitIdsPerTokenId = new uint256[](length);
        uint256 traitIdsLengthPerTokenId = 0;
       
        uint256[] memory amounts = new uint256[](length);
        unchecked {
            uint256 prevTokenId;
            uint256 mask;
            for (uint i=0; i<length; ++i) {
                uint256 tokenId = tokenIds[i];
                if (tokenId != prevTokenId) {
                    require(tokenId > prevTokenId, 'tokenIds must be in ascending order');

                    if (traitIdsLengthPerTokenId > 0) {
                        // set length of temp array
                        assembly {
                            mstore(traitIdsPerTokenId, traitIdsLengthPerTokenId)
                        }
                        emit ApplyTraits(msg.sender, prevTokenId, traitIdsPerTokenId);
                        traitIdsLengthPerTokenId = 0;
                    }

                    prevTokenId = tokenId;
                    mask = 0;

                    require(IERC721(_tokenContract).ownerOf(tokenId) == msg.sender, 'Not owner of tokenId');
                }

                uint256 traitId = traitIds[i];
                uint256 traitMask = traitIds[i] >> 16;
                require((mask & traitMask) == 0, 'Cannot apply multiple traits to same part');
                mask |= traitMask;

                amounts[i] = 1;
                // same as traitIdsPerTokenId[traitIdsLengthPerTokenId++] = traitId; but without
                // solidity bounds checking which may fail because final length is not set yet
                traitIdsLengthPerTokenId++;
                assembly {
                    mstore(add(traitIdsPerTokenId, shl(5, traitIdsLengthPerTokenId)), traitId)
                }
            }

            if (traitIdsLengthPerTokenId > 0) {
                // set length of temp array
                assembly {
                   mstore(traitIdsPerTokenId, traitIdsLengthPerTokenId)
                }
                emit ApplyTraits(msg.sender, prevTokenId, traitIdsPerTokenId);
            }
        }

        Traits(_traitsContract).burnBatch(msg.sender, traitIds, amounts);
    }
    

    function applyTraitsToToken(uint256[] calldata traitIds, uint256 tokenId) external canApply {
        uint length = traitIds.length;
        require(length > 0, "Invalid array length");

        require(IERC721(_tokenContract).ownerOf(tokenId) == msg.sender, 'Not owner of tokenId');

        emit ApplyTraits(msg.sender, tokenId, traitIds);

        uint256[] memory amounts = new uint256[](length);
        unchecked {
            uint256 mask;
            for (uint i=0; i<length; ++i) {
                uint256 traitMask = traitIds[i] >> 16;
                require((mask & traitMask) == 0, 'Cannot apply multiple traits to same part');
                mask |= traitMask;
                amounts[i] = 1;
            }
        }

        Traits(_traitsContract).burnBatch(msg.sender, traitIds, amounts);
    }

  
    function applyPeriod() external view returns (uint256 startBlockNumber, uint256 endTimestamp, bool isEnabled) {
        startBlockNumber = _startBlockNumber;
        endTimestamp = _deadlineTimestamp;
        isEnabled = _isEnabled;
    }

    function setNewApplyDeadline(uint48 timestamp) external onlyOwner {
        require(timestamp > block.timestamp, "Must be timestamp in the future");
        require(_deadlineTimestamp < block.timestamp, "Current deadline has not passed yet, use updateApplyDeadline");
        _deadlineTimestamp = timestamp;
        _startBlockNumber = uint48(block.number);

        emit ApplyPeriod(_startBlockNumber, _deadlineTimestamp);
    }

    /**
     * @dev Only to be used when the existing deadline needs to be extended
     */
    function updateApplyDeadline(uint48 timestamp) external onlyOwner {
        require(_startBlockNumber > 0, "Current deadline has not been set");
        require(timestamp > block.timestamp, "Must be timestamp in the future");
        _deadlineTimestamp = timestamp;

        emit ApplyPeriod(_startBlockNumber, _deadlineTimestamp);
    }

    function setApplyEnabled(bool enabled) external onlyOwner {
        _isEnabled = enabled;
    }
}
