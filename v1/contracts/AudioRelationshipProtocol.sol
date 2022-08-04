//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import "../interfaces/IAudioRelationshipProtocol.sol";

////////////////////////////////////////////////////////////////////////////////////////
//                       ___                              _   _           _           //
//   ┌──┬──┬─┬──┬──┐    / _ \                            (_) | |         | |          //
//   │  │  │ │  │  │   / /_\ \_ __ _ __   ___  __ _  __ _ _  | |     __ _| |__  ___   //
//   │  │  │ │  │  │   |  _  | '__| '_ \ / _ \/ _` |/ _` | | | |    / _` | '_ \/ __|  //
//   │  └┬─┘ └─┬┘  │   | | | | |  | |_) |  __/ (_| | (_| | | | |___| (_| | |_) \__ \  //
//   │   │     │   │   \_| |_/_|  | .__/ \___|\__, |\__, |_| \_____/\__,_|_.__/|___/  //
//   └───┴─────┴───┘              | |          __/ | __/ |                            //
//                                |_|         |___/ |___/                             //
//                                                                                    //
////////////////////////////////////////////////////////////////////////////////////////

/// @title Audio Relationship Protocol (ARP) v1.0
/// @author Alec Papierniak <alec@arpeggi.io>, Kyle Dhillon <kyle@arpeggi.io>
/// @notice This composability protocol enables artists and dapps to register media to make it available for permissionless reuse with attribution.
contract AudioRelationshipProtocol is Initializable, AccessControlUpgradeable, PausableUpgradeable, UUPSUpgradeable, IAudioRelationshipProtocol {
    /// @dev Role required to upgrade the ARP contract
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @dev Role required to overwrite existing media within ARP
    bytes32 public constant OVERWRITER_ROLE = keccak256("OVERWRITER_ROLE");

    /// @dev Role required to pause/unpause the ability to register media
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @dev Role required to register media while `_requireAuthorizedWriter` is enabled
    bytes32 public constant AUTHORIZED_WRITER_ROLE = keccak256("AUTHORIZED_WRITER_ROLE");

    /// @notice Tracks the number of media registered within ARP
    /// @dev Initialized to 0
    uint256 public _numMedia;

    /// @notice A limit on the number of subcomponents allowed for registered media with ARP
    /// @dev Enforced when `_enforceMaxSubComponents` is true initialized to 1200
    uint256 public _maxSubComponents;

    /// @notice Current version of the ARP format
    /// @dev Initialized to 1
    uint256 public _version;

    /// @notice When true, cap the number of subcomponents allowed when registering media to ARP
    /// @dev Initialized to true
    bool public _enforceMaxSubComponents;

    /// @notice When true, require caller to have `AUTHORIZED_WRITER_ROLE` role when registering media to ARP
    /// @dev Initialized to true
    bool public _requireAuthorizedWriter;

    /// @notice Mapping to store all media registered within ARP
    /// @dev ARP Media ID => ARP Media
    mapping(uint256 => Media) public _media;

    /// @notice Mapping used to lookup ARP media by primary origin token details.
    /// @dev chainId => contract address => tokenId => mediaId
    mapping(uint256 => mapping(address => mapping(uint256 => uint256))) public _originTokenToMediaId;

    /// @notice Emitted when media is registered
    /// @param mediaId ARP Media ID of the newly registered media
    /// @param artistAddress Address of the artist for the newly registered media
    event MediaRegistered(uint256 indexed mediaId, address indexed artistAddress);

    /// @notice OpenZeppelin initializer function
    function initialize() public initializer {
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(UPGRADER_ROLE, _msgSender());
        _grantRole(OVERWRITER_ROLE, _msgSender());
        _grantRole(PAUSER_ROLE, _msgSender());
        _grantRole(AUTHORIZED_WRITER_ROLE, _msgSender());

        _numMedia = 0;
        _maxSubComponents = 1200;
        _enforceMaxSubComponents = true;
        _version = 1;
        _requireAuthorizedWriter = true;
    }

    /// @notice Registers media to the ARP protocol. All registered media must already be released under a CC0 License.
    /// @dev ARP metadata schema https://nice-splash-d53.notion.site/ARP-Metadata-Schema-cb63cc22a9a24b0cb19ad852f400c153
    /// @param artistAddress address of the artist who created this media
    /// @param dataUri URL of the actual data
    /// @param metadataUri JSON string describing the metadata (or, URL of the JSON string), following the ARP metadata schema
    /// @param subcomponents array of ARP IDs of subcomponents used in this media (e.g. list of samples used in a stem)
    /// @param originContractAddress Contract address of origin token
    /// @param originTokenId Token ID of origin token
    /// @param originChainId Chain ID on which the origin token resides
    /// @param originType OriginType of the origin token. Options are PRIMARY and SECONDARY.
    /// @return the ARP ID of the newly registered media
    function registerMedia(
        address artistAddress,
        string calldata dataUri,
        string calldata metadataUri,
        uint256[] calldata subcomponents,
        address originContractAddress,
        uint256 originTokenId,
        uint256 originChainId,
        uint8 originType
    ) external whenNotPaused returns (uint256) {
        if (_requireAuthorizedWriter) {
            require(hasRole(AUTHORIZED_WRITER_ROLE, _msgSender()), "ARP: Unauthorized write.");
        }

        if (_enforceMaxSubComponents) {
            require(subcomponents.length < _maxSubComponents, "ARP: Too many subcomponents.");
        }

        if (subcomponents.length > 0) {
            for (uint256 i = 0; i < subcomponents.length; i++) {
                require(subcomponents[i] <= _numMedia, "ARP: Invalid subcomponent.");
            }
        }
        _numMedia++;

        _media[_numMedia].mediaId = _numMedia;
        _media[_numMedia].version = _version;
        _media[_numMedia].artistAddress = artistAddress;
        _media[_numMedia].dataUri = dataUri;
        _media[_numMedia].metadataUri = metadataUri;

        if (subcomponents.length > 0) {
            _media[_numMedia].subcomponents = subcomponents;
        }

        if (originTokenId > 0 && originContractAddress != address(0)) {
            if (originChainId == block.chainid) {
                require(IERC721(originContractAddress).ownerOf(originTokenId) != address(0), "ARP: Origin token must exist.");
            }

            // only allow a single PRIMARY origin token type
            if (OriginType(originType) == OriginType.PRIMARY) {
                require(!primaryOriginTypeExists(originContractAddress, originTokenId, originChainId), "ARP: Primary origin already registered.");
            }

            _media[_numMedia].originToken.tokenId = originTokenId;
            _media[_numMedia].originToken.contractAddress = originContractAddress;
            _media[_numMedia].originToken.chainId = originChainId;
            _media[_numMedia].originToken.originType = OriginType(originType);
            _originTokenToMediaId[originChainId][originContractAddress][originTokenId] = _numMedia;
        }

        emit MediaRegistered(_numMedia, artistAddress);

        return _numMedia;
    }

    /// @notice Fetches ARP Media by ID
    /// @param index ARP Media ID of the requested media
    /// @return The ARP Media, if exists
    function getMedia(uint256 index) external view returns (Media memory) {
        require(index <= _numMedia, "Invalid index.");
        return _media[index];
    }

    /// @notice Fetches media by origin token details
    /// @param tokenId The ID of the origin token on the origin contract
    /// @param contractAddress The address of the origin contract
    /// @return The ARP media, if any exists
    function getMediaByOrigin(
        uint256 chainId,
        address contractAddress,
        uint256 tokenId
    ) external view returns (Media memory) {
        uint256 index = _originTokenToMediaId[chainId][contractAddress][tokenId];
        require(index > 0, "ARP: No media for origin data."); // problem with zero index
        return _media[index];
    }

    /// @notice Determine if media has already been registered as primary type for a given origin token
    /// @param contractAddress The origin token to check
    /// @param tokenId The ID of the origin token
    /// @param chainId The chain where the origin token contract resides
    /// @return true when primary has already been registered, false otherwise
    function primaryOriginTypeExists(
        address contractAddress,
        uint256 tokenId,
        uint256 chainId
    ) internal view returns (bool) {
        return _originTokenToMediaId[chainId][contractAddress][tokenId] != 0;
    }

    /// @notice Determine if caller should be allowed to overwrite existing ARP Media
    /// @dev Requires msg.sender to have `OVERWRITER_ROLE` role, or caller to be the artist of the target ARP Media
    /// @param chainId The chain on which the origin token resides
    /// @param contractAddress The contract for the origin token
    /// @param tokenId The ID of the origin token
    /// @return bool true if the caller is allowed to overwrite the record within ARP, otherwise revert
    function enforceOnlyOverwriteAuthorized(
        uint256 chainId,
        address contractAddress,
        uint256 tokenId
    ) internal view returns (bool) {
        // check if the caller has overwriter role
        if (hasRole(OVERWRITER_ROLE, msg.sender)) {
            return true;
        }

        // otherwise, only allow the artist to overwrite
        Media memory media = _media[_originTokenToMediaId[chainId][contractAddress][tokenId]];

        if (media.artistAddress == msg.sender) {
            return true;
        }

        revert("ARP: Forbidden overwrite.");
    }

    /// @notice Set the current version of ARP to be using during media registration
    /// @param newVersion New version number of ARP to be set
    function setVersion(uint256 newVersion) public onlyRole(UPGRADER_ROLE) {
        _version = newVersion;
    }

    /// @notice Sets the number of subcomponents allowed when registering a piece of media
    function setMaxSubComponents(uint256 maxSubComponents) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _maxSubComponents = maxSubComponents;
    }

    /// @notice Enables/disables enforcing the max number of subcomponents allowed when registering a piece of media
    function setEnforceMaxSubComponents(bool enforceMaxSubComponents) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _enforceMaxSubComponents = enforceMaxSubComponents;
    }

    /// @notice Enable or disable requiring an authorized writer to register media
    function setRequireAuthorizedWriter(bool requireAuthorizedWriter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _requireAuthorizedWriter = requireAuthorizedWriter;
    }

    /// @notice Pause registration of media
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Unpause registraion of media
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @notice ERC165
    function supportsInterface(bytes4 interfaceId) public view override(AccessControlUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /// @notice Upgrading the contract requires the UPGRADER_ROLE
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}
