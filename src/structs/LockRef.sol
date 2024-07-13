// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.24;

/// @notice Struct for representing a lock.
struct Lock {
    bool isUnlocked;
    uint256[] checkedOutItems; // items checked out while the lock is unlocked
}

using LockLibrary for Lock global;

/// @notice Library for working with lock.
library LockLibrary {
    /// @notice Thrown when trying to check out an item while the lock is not unlocked.
    error LockNotUnlocked();

    /// @notice Thrown when trying to lock the lock while not every item is checked in.
    error ItemsNotCheckedIn();

    /// @notice Unlocks the lock.
    /// @param s_self The lock to unlock
    function unlock(Lock storage s_self) internal {
        s_self.isUnlocked = true;
    }

    /// @notice Locks the lock.
    /// @param s_self The lock to lock
    function lock(Lock storage s_self) internal {
        if (s_self.checkedOutItems.length != 0) revert ItemsNotCheckedIn();

        s_self.isUnlocked = false;
    }

    /// @notice Checks out an item when the lock is unlocked.
    /// @param s_self The lock to check out under
    /// @param item The item to check out
    function checkOut(Lock storage s_self, uint256 item) internal {
        if (!s_self.isUnlocked) revert LockNotUnlocked();

        // opt to loop a short array instead of supporing random access
        uint256[] memory checkedOutItems = s_self.checkedOutItems;
        for (uint256 i = 0; i < checkedOutItems.length; i++) {
            if (checkedOutItems[i] == item) {
                return;
            }
        }

        s_self.checkedOutItems.push(item);
    }

    /// @notice Checks in every checked out item.
    /// @param s_self The lock to check in under
    function checkInAll(Lock storage s_self) internal {
        delete s_self.checkedOutItems;
    }
}
