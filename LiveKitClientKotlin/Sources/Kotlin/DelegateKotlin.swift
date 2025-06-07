import Foundation
import LiveKitClient

@objc
public class DelegateKotlin: NSObject {
    @objc
    public func appendTo(room roomParam: Room, delegate: RoomDelegate) {
        roomParam.add(delegate: delegate)
    }

    @objc
    public func appendTo(participant participantParam: Participant, delegate: ParticipantDelegate) {
        participantParam.add(delegate: delegate)
    }

    @objc
    public func wrapRoomDelegateWith(delegate: RoomDelegate) -> RoomDelegate
    {
        return RoomDelegateKotlin(delegate: delegate)
    }

    @objc
    public func wrapParticipantDelegateWith(delegate: ParticipantDelegate) -> ParticipantDelegate
    {
        return ParticipantDelegateKotlin(delegate: delegate)
    }
}