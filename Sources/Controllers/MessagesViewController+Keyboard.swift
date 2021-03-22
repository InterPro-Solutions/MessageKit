/*
 MIT License

 Copyright (c) 2017-2020 MessageKit

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
 */

import Foundation
import UIKit
import InputBarAccessoryView

internal extension MessagesViewController {

    // MARK: - Register / Unregister Observers

    func addKeyboardObservers() {
        let token = messageInputBar.observe(\.center, options: .new, changeHandler: {
            [weak self] inputBar, changedCenter in
            guard let self = self else {
                return
            }
            let inputViewFrame  = self.view.convert(inputBar.frame, from: inputBar.superview ?? self.view.window)

            let newBottomInset = max(0, max (0, self.messagesCollectionView.frame.maxY - inputViewFrame.minY) + self.additionalBottomInset - self.automaticallyAddedBottomInset)
            let differenceOfBottomInset = newBottomInset - self.messageCollectionViewBottomInset

            defer {
                UIView.performWithoutAnimation {
                    self.messageCollectionViewBottomInset = newBottomInset
                }
            }
            if self.maintainPositionOnKeyboardFrameChanged && differenceOfBottomInset != 0 {
                let contentOffset = CGPoint(x: self.messagesCollectionView.contentOffset.x, y: self.messagesCollectionView.contentOffset.y + differenceOfBottomInset)
                    // Changing contentOffset to bigger number than the contentSize will result in a jump of content
                    // https://github.com/MessageKit/MessageKit/issues/1486
                guard contentOffset.y <= self.messagesCollectionView.contentSize.height else {
                    return
                }
                self.messagesCollectionView.setContentOffset(contentOffset, animated: false)
            }
        })
        self.kvoTokenSet.insert(token)
        //NotificationCenter.default.addObserver(self, selector: #selector(MessagesViewController.handleKeyboardDidChangeState(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(MessagesViewController.handleTextViewDidBeginEditing(_:)), name: UITextView.textDidBeginEditingNotification, object: nil)
    }

    func removeKeyboardObservers() {
        //NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UITextView.textDidBeginEditingNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
        for token in kvoTokenSet{
            token.invalidate()
        }
    }

    @objc
    private func messageInputBarDidLayoutSubview(_ notification: Notification) {
        let inputViewFrame  = view.convert(messageInputBar.frame, from: messageInputBar.superview ?? view.window)

        let newBottomInset = max(0, max (0, messagesCollectionView.frame.maxY - inputViewFrame.minY) + additionalBottomInset - automaticallyAddedBottomInset)
        let differenceOfBottomInset = newBottomInset - messageCollectionViewBottomInset

        defer {
            UIView.performWithoutAnimation {
                messageCollectionViewBottomInset = newBottomInset
            }
        }
        if maintainPositionOnKeyboardFrameChanged && differenceOfBottomInset != 0 {
            let contentOffset = CGPoint(x: messagesCollectionView.contentOffset.x, y: messagesCollectionView.contentOffset.y + differenceOfBottomInset)
                // Changing contentOffset to bigger number than the contentSize will result in a jump of content
                // https://github.com/MessageKit/MessageKit/issues/1486
            guard contentOffset.y <= messagesCollectionView.contentSize.height else {
                return
            }
            messagesCollectionView.setContentOffset(contentOffset, animated: false)
        }
    }

    // MARK: - Notification Handlers

    @objc
    private func handleTextViewDidBeginEditing(_ notification: Notification) {
        if scrollsToLastItemOnKeyboardBeginsEditing || scrollsToLastItemOnKeyboardBeginsEditing {
            guard
                let inputTextView = notification.object as? InputTextView,
                inputTextView === messageInputBar.inputTextView
            else {
                return
            }
            if scrollsToLastItemOnKeyboardBeginsEditing {
                messagesCollectionView.scrollToLastItem()
            } else {
                messagesCollectionView.scrollToLastItem(animated: true)
            }
        }
    }

    @objc
    private func handleKeyboardDidChangeState(_ notification: Notification) {
        guard !isMessagesControllerBeingDismissed else { return }

        guard let keyboardStartFrameInScreenCoords = notification.userInfo?[UIResponder.keyboardFrameBeginUserInfoKey] as? CGRect else { return }
        guard !keyboardStartFrameInScreenCoords.isEmpty || UIDevice.current.userInterfaceIdiom != .pad else {
            // WORKAROUND for what seems to be a bug in iPad's keyboard handling in iOS 11: we receive an extra spurious frame change
            // notification when undocking the keyboard, with a zero starting frame and an incorrect end frame. The workaround is to
            // ignore this notification.
            return
        }

        guard self.presentedViewController == nil else {
            // This is important to skip notifications from child modal controllers in iOS >= 13.0
            return
        }

        // Note that the check above does not exclude all notifications from an undocked keyboard, only the weird ones.
        //
        // We've tried following Apple's recommended approach of tracking UIKeyboardWillShow / UIKeyboardDidHide and ignoring frame
        // change notifications while the keyboard is hidden or undocked (undocked keyboard is considered hidden by those events).
        // Unfortunately, we do care about the difference between hidden and undocked, because we have an input bar which is at the
        // bottom when the keyboard is hidden, and is tied to the keyboard when it's undocked.
        //
        // If we follow what Apple recommends and ignore notifications while the keyboard is hidden/undocked, we get an extra inset
        // at the bottom when the undocked keyboard is visible (the inset that tries to compensate for the missing input bar).
        // (Alternatives like setting newBottomInset to 0 or to the height of the input bar don't work either.)
        //
        // We could make it work by adding extra checks for the state of the keyboard and compensating accordingly, but it seems easier
        // to simply check whether the current keyboard frame, whatever it is (even when undocked), covers the bottom of the collection
        // view.

        guard let keyboardEndFrameInScreenCoords = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let keyboardEndFrame = view.convert(keyboardEndFrameInScreenCoords, from: view.window)

        let newBottomInset = requiredScrollViewBottomInset(forKeyboardFrame: keyboardEndFrame)
        let differenceOfBottomInset = newBottomInset - messageCollectionViewBottomInset

        defer {
            UIView.performWithoutAnimation {
                messageCollectionViewBottomInset = newBottomInset
            }
        }
        if maintainPositionOnKeyboardFrameChanged && differenceOfBottomInset != 0 {
            let contentOffset = CGPoint(x: messagesCollectionView.contentOffset.x, y: messagesCollectionView.contentOffset.y + differenceOfBottomInset)
            // Changing contentOffset to bigger number than the contentSize will result in a jump of content
            // https://github.com/MessageKit/MessageKit/issues/1486
            guard contentOffset.y <= messagesCollectionView.contentSize.height else {
                return
            }
            messagesCollectionView.setContentOffset(contentOffset, animated: false)
        }
    }

    // MARK: - Inset Computation

    private func requiredScrollViewBottomInset(forKeyboardFrame keyboardFrame: CGRect) -> CGFloat {
        // we only need to adjust for the part of the keyboard that covers (i.e. intersects) our collection view;
        // see https://developer.apple.com/videos/play/wwdc2017/242/ for more details
        let intersectionWithKeyboard = messagesCollectionView.frame.intersection(keyboardFrame)
        let messagesViewFrame = messagesCollectionView.frame

        print("maxY:\(messagesViewFrame.maxY),height:\(messagesViewFrame.height)")
        var result : CGFloat = 0
        if intersectionWithKeyboard.isNull || (messagesCollectionView.frame.maxY - intersectionWithKeyboard.maxY) > 0.001 {
            // The keyboard is hidden, is a hardware one, or is undocked and does not cover the bottom of the collection view.
            // Note: intersection.maxY may be less than messagesCollectionView.frame.maxY when dealing with undocked keyboards.

            result = max(0, additionalBottomInset - automaticallyAddedBottomInset)
        } else {
            result = max(0, intersectionWithKeyboard.height + additionalBottomInset - automaticallyAddedBottomInset)
        }
        print("result: \(result)")
        return result
    }

    func requiredInitialScrollViewBottomInset() -> CGFloat {
        let inputAccessoryViewHeight = inputAccessoryView?.frame.height ?? 0
        return max(0, inputAccessoryViewHeight + additionalBottomInset - automaticallyAddedBottomInset)
    }

    /// UIScrollView can automatically add safe area insets to its contentInset,
    /// which needs to be accounted for when setting the contentInset based on screen coordinates.
    ///
    /// - Returns: The distance automatically added to contentInset.bottom, if any.
    private var automaticallyAddedBottomInset: CGFloat {
        return messagesCollectionView.adjustedContentInset.bottom - messagesCollectionView.contentInset.bottom
    }
}
