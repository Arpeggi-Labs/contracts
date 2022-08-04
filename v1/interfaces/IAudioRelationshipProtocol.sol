//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.9;

interface IAudioRelationshipProtocol {
    /// @notice Schema for ARP Media stored within ARP
    /// @param mediaId the ARP ID of the registered media
    /// @param version the schema version of the registered media 
    /// @param artistAddress address of the artist who created this media
    /// @param dataUri URL of the actual data
    /// @param metadataUri JSON string describing the metadata (or, URL of the JSON string), following the ARP metadata schema
    /// @param subcomponents array of ARP IDs of subcomponents used in this media (e.g. list of samples used in a stem)
    /// @param originToken optional reference to any ERC-721 compliant token on any EVM-compatible chain representing this media
    struct Media {
        uint256 mediaId;
        uint256 version;
        address artistAddress;
        string dataUri;
        string metadataUri;
        uint256[] subcomponents;
        OriginToken originToken;
    }

    /// @notice A reference to any ERC-721 compliant token on any EVM-compatible chain.
    /// @param tokenId token ID
    /// @param chainId chain ID of the contract this token is on. See https://chainlist.org/
    /// @param contractAddress contract address for this token
    /// @param originType the OriginType of this item. Usually PRIMARY, unless registering multiple media elements with the same OriginToken.
    struct OriginToken {
        uint256 tokenId;
        uint256 chainId;
        address contractAddress;
        OriginType originType;
    }

    /// @notice Indicates whether this is the primary media that corresponds to
    ///    a referenced token, so that when a user calls `getMediaByOrigin()`, ARP will
    ///    only return the PRIMARY media and ignore the SECNODARY.
    ///    There can only be one PRIMARY media registered in ARP for each ERC-721 token.
    enum OriginType {
        PRIMARY,
        SECONDARY
    }

    /// @notice Registers media to the ARP protocol. All registered media must already be released under a CC0 License.
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
    ) external returns (uint256);

    /// @notice Fetches ARP Media by ID
    /// @param index ARP Media ID of the requested media
    /// @return The ARP Media, if exists
    function getMedia(uint256 index) external view returns (Media memory);

    /// @notice Fetches media by origin token details
    /// @param tokenId The ID of the origin token on the origin contract
    /// @param contractAddress The address of the origin contract
    /// @return The ARP media, if any exists
    function getMediaByOrigin(
        uint256 chainId,
        address contractAddress,
        uint256 tokenId
    ) external view returns (Media memory);
}
