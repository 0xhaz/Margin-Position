// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity >=0.8.0;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IERC721TokenReceiver} from "forge-std/interfaces/IERC721.sol";
import {Fungible} from "src/types/Fungible.sol";
import {NonFungible} from "src/types/NonFungible.sol";
import {IRiskConfigs} from "src/interfaces/IRiskConfigs.sol";

/// @notice Interface for the Ampli Protocol
interface IAmpli is IERC20, IERC721TokenReceiver, IRiskConfigs {
    /// @notice Emitted when a position is opened
    /// @param positionId The position ID
    /// @param owner The position owner
    /// @param originator The position originator
    event PositionOpened(uint256 indexed positionId, address indexed owner, address indexed originator);

    /// @notice Emitted when a position is closed
    /// @param positionId The position ID
    event PositionClosed(uint256 indexed positionId);

    /// @notice Emitted when some amount of a fungible is deposited into a position
    /// @param positionId The position ID
    /// @param operator The operator of the deposit
    /// @param fungible The fungible deposited
    /// @param amount The amount deposited
    event FungibleDeposited(
        uint256 indexed positionId, address indexed operator, Fungible indexed fungible, uint256 amount
    );

    /// @notice Emitted when some amount of a fungible is withdrawn from a position
    /// @param positionId The position ID
    /// @param recipient The recipient of the withdrawal
    /// @param fungible The fungible withdrawn
    /// @param amount The amount withdrawn
    event FungibleWithdrawn(
        uint256 indexed positionId, address indexed recipient, Fungible indexed fungible, uint256 amount
    );

    /// @notice Emitted when a non-fungible item is deposited into a position.
    /// @param positionId The position ID
    /// @param operator The operator of the deposit
    /// @param nonFungible The non-fungible deposited
    /// @param item The item deposited
    event NonFungibleDeposited(
        uint256 indexed positionId, address indexed operator, NonFungible indexed nonFungible, uint256 item
    );

    /// @notice Emitted when a non-fungible item is withdrawn from a position.
    /// @param positionId The position ID
    /// @param recipient The recipient of the withdrawal
    /// @param nonFungible The non-fungible withdrawn
    /// @param item The item withdrawn
    event NonFungibleWithdrawn(
        uint256 indexed positionId, address indexed recipient, NonFungible indexed nonFungible, uint256 item
    );

    /// @notice Emitted when PED is borrowed through a position.
    /// @param positionId The position ID
    /// @param recipient The recipient of the PED
    /// @param nominalAmount The nominal amount borrowed
    /// @param realAmount The real amount borrowed
    event Borrow(uint256 indexed positionId, address indexed recipient, uint256 nominalAmount, uint256 realAmount);

    /// @notice Emitted when PED is repaid through a position.
    /// @param positionId The position ID
    /// @param nominalAmount The nominal amount repaid
    /// @param realAmount The real amount repaid
    event Repay(uint256 indexed positionId, uint256 nominalAmount, uint256 realAmount);

    /// @notice Emitted when a position is liquidated.
    /// @param positionId The position ID
    /// @param liquidator The liquidator of the liquidation
    /// @param recipient The recipient of the position
    /// @param relief The relief provided by protocol in PED
    /// @param shortfall The shortfall to be provided by liquidator in PED
    event Liquidate(
        uint256 indexed positionId,
        address indexed liquidator,
        address indexed recipient,
        uint256 relief,
        uint256 shortfall
    );

    /// @notice Emitted when native fungibles are exchanged for PED.
    /// @param operator The operator of the exchange
    /// @param recipient The recipient of the PED
    /// @param nativeAmount The amount of native fungibles exchanged
    /// @param amount The amount of PED received
    event Exchange(address indexed operator, address indexed recipient, uint256 nativeAmount, uint256 amount);

    /// @notice Emitted when deficit is settled in PED.
    /// @param operator The operator of the settlement
    /// @param amount The amount settled in PED
    event Settle(address indexed operator, uint256 amount);

    /// @notice Emitted when surplus is collected in native fungibles.
    /// @param recipient The recipient of the surplus
    /// @param nativeAmount The amount collected in native fungibles
    event Collect(address indexed recipient, uint256 nativeAmount);

    /// @notice Thrown when the caller is not the owner of a position.
    error NotOwner();

    /// @notice Thrown when trying to interact with a non-existent position.
    error PositionDoesNotExist();

    /// @notice Thrown when trying to liquidate a position that is not at risk.
    error PositionNotAtRisk();

    /// @notice Thrown when some interactions with a position left it at risk.
    error PositionAtRisk(uint256 positionId);

    /// @notice Thrown when trying to deposit more fungbles than is received.
    error FungibleAmountNotRecieved();

    /// @notice Thrown when trying to withdraw more fungibs than is available.
    error FungibleBalanceInsufficient();

    /// @notice Thrown when trying to deposit a non-fungible item that is not received.
    error NonFungibleItemNotRecieved();

    /// @notice Thrown when trying to deposit a non-fungible item that is already deposited.
    error NonFungibleItemAlreadyDeposited();

    /// @notice Thrown when trying to withdraw a non-fungible item that is not in the position.
    error NonFungibleItemNotInPosition();

    /// @notice Thrown when trying collect more surplus than is available.
    error InsufficientSurplus();

    /// @notice Unlocks the protocol for sensitive operations.
    /// @param callbackData The data for the callback
    /// @return callbackResult The result of the callback
    function unlock(bytes calldata callbackData) external returns (bytes memory callbackResult);

    /// @notice Opens a new position.
    /// @param originator The originator of the position
    /// @return positionId The position ID
    function openPosition(address originator) external returns (uint256 positionId);

    /// @notice Closes a position.
    /// @param positionId The position ID
    function closePosition(uint256 positionId) external;

    /// @notice Deposits some amount of a fungible into a position.
    /// @param positionId The position ID
    /// @param fungible The fungible to deposit
    /// @param amount The amount to deposit
    function depositFungible(uint256 positionId, Fungible fungible, uint256 amount) external payable;

    /// @notice Withdraws some amount of a fungible from a position.
    /// @param positionId The position ID
    /// @param fungible The fungible to withdraw
    /// @param amount The amount to withdraw
    /// @param recipient The recipient of the withdrawal
    function withdrawFungible(uint256 positionId, Fungible fungible, uint256 amount, address recipient) external;

    /// @notice Deposits a non-fungible item into a position.
    /// @param positionId The position ID
    /// @param nonFungible The non-fungible to deposit
    /// @param item The item to deposit
    function depositNonFungible(uint256 positionId, NonFungible nonFungible, uint256 item) external;

    /// @notice Withdraws a non-fungible item from a position.
    /// @param positionId The position ID
    /// @param nonFungible The non-fungible to withdraw
    /// @param item The item to withdraw
    /// @param recipient The recipient of the withdrawal
    function withdrawNonFungible(uint256 positionId, NonFungible nonFungible, uint256 item, address recipient)
        external;

    /// @notice Borrows some amount of PED through a position.
    /// @param positionId The position ID
    /// @param amount The amount to borrow
    /// @param recipient The recipient of the PED
    function borrow(uint256 positionId, uint256 amount, address recipient) external;

    /// @notice Repays some amount of PED through a position.
    /// @param positionId The position ID
    /// @param amount The amount to repay
    function repay(uint256 positionId, uint256 amount) external;

    /// @notice Liquidates a position.
    /// @param positionId The position ID
    /// @param recipient The recipient of the position
    /// @return shortfall The shortfall to be provided by liquidator in PED
    function liquidate(uint256 positionId, address recipient) external returns (uint256 shortfall);

    /// @notice Exchanges native fungibles for PED.
    /// @param recipient The recipient of the PED
    function exchange(address recipient) external payable;

    /// @notice Settles deficit in PED, the lesser of the deficit and the balance.
    function settle() external;

    /// @notice Collects surplus in native fungibles.
    /// @param recipient The recipient of the surplus
    /// @param amount The amount to collect
    function collect(address recipient, uint256 amount) external;

    /// @notice Gets the next position ID.
    /// @return positionId The next position ID
    function nextPositionId() external view returns (uint256);

    /// @notice Gets the deficit of the protocol.
    /// @return deficit The deficit of the protocol
    function deficit() external view returns (uint256);

    /// @notice Gets the surplus of the protocol.
    /// @return surplus The surplus of the protocol
    function surplus() external view returns (uint256);

    /// @notice Gets the owner of a position.
    /// @param positionId The position ID
    /// @return owner The owner of the position
    function ownerOf(uint256 positionId) external view returns (address owner);

    /// @notice Gets the originator of a position.
    /// @param positionId The position ID
    /// @return originator The originator of the position
    function originatorOf(uint256 positionId) external view returns (address originator);

    /// @notice Gets the balance of a fungible in a position.
    /// @param positionId The position ID
    /// @param fungible The fungible
    /// @return balance The balance of the fungible
    function balanceOf(uint256 positionId, Fungible fungible) external view returns (uint256 balance);

    /// @notice Gets the items count of a non-fungible in a position.
    /// @param positionId The position ID
    /// @param nonFungible The non-fungible
    /// @return count The items count of the non-fungible
    function itemsCountOf(uint256 positionId, NonFungible nonFungible) external view returns (uint256 count);

    /// @notice Gets the position ID of a non-fungible item.
    /// @param nonFungible The non-fungible
    /// @param item The item
    /// @return positionId The position ID of the non-fungible item
    function positionOf(NonFungible nonFungible, uint256 item) external view returns (uint256 positionId);

    /// @notice Gets the global balance of a fungible.
    /// @param fungible The fungible
    /// @return balance The global balance of the fungible
    function globalBalanceOf(Fungible fungible) external view returns (uint256 balance);

    /// @notice Gets the global items count of a non-fungible.
    /// @param nonFungible The non-fungible
    /// @return count The global items count of the non-fungible
    function globalItemsCountOf(NonFungible nonFungible) external view returns (uint256 count);
}
