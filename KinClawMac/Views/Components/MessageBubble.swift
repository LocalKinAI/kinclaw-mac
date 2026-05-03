import SwiftUI
import AVFoundation

struct MessageBubble: View {
    let message: ChatMessage
    var agentSlug: String = ""
    var agentDomain: String = ""
    var hostname: String = ""
    @StateObject private var speaker = SpeechSynthesizer()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isUser { Spacer(minLength: 60) }

            if !message.isUser {
                let icon = AgentListView.agentIcon(agentSlug, domain: agentDomain)
                let color = AgentListView.domainColor(agentDomain)
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
                    .frame(width: 28, height: 28)
                    .background(Color.platformTertiaryBackground)
                    .clipShape(Circle())
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(LocalizedStringKey(message.content))
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        message.isUser
                            ? Color.green.opacity(0.2)
                            : Color.platformSecondaryBackground
                    )
                    .foregroundColor(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                HStack(spacing: 8) {
                    Text(timeString)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    // TTS button for agent messages
                    if !message.isUser && !message.content.isEmpty {
                        Button {
                            if speaker.isSpeaking {
                                speaker.stop()
                            } else {
                                speaker.speak(message.content, hostname: hostname) {}
                            }
                        } label: {
                            Image(systemName: speaker.isSpeaking ? "stop.circle.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 12))
                                .foregroundColor(speaker.isSpeaking ? .orange : .secondary)
                        }
                    }
                }
            }

            if !message.isUser { Spacer(minLength: 60) }
        }
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: message.timestamp)
    }
}
