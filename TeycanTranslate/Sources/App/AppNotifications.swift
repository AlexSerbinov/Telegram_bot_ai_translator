import Foundation

extension Notification.Name {
    /// Posted by MainTabView whenever the active tab changes. UserInfo:
    ///  - "from": String (raw value of leaving tab, e.g. "companion")
    ///  - "to":   String (raw value of newly active tab)
    ///
    /// Session managers listen on this and call their own `hardStop` when they
    /// detect their tab has been left — preventing leaked WebRTC peers from
    /// burning OpenAI tokens in the background.
    static let teycanTabChanged = Notification.Name("solutions.techchain.teycan.tabChanged")
}
