import SwiftUI

// MARK: - Data Models
struct Message: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isFromUser: Bool
    var isTyping: Bool = false
}

// --- NEW: Data Model for Debate Topics ---
struct DebateTopic: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let description: String
    let initialAIPrompt: String
}

// MARK: - App Entry Point: The Topic Selection Screen
struct EthosView: View {
    
    @State private var showDisclaimer = true
    
    // --- NEW: Pre-defined list of debate starters ---
    private let topics: [DebateTopic] = [
        DebateTopic(
            title: "The Cosmological Argument",
            description: "Does the universe require a first cause?",
            initialAIPrompt: "You've chosen to discuss the Kalam Cosmological Argument. Let's begin with the first premise: 'Everything that begins to exist has a cause.' Do you accept this premise as sound?"
        ),
        DebateTopic(
            title: "The Teleological Argument",
            description: "Does the fine-tuning of the universe point to a designer?",
            initialAIPrompt: "You wish to explore the Teleological, or 'Fine-Tuning,' Argument. The core claim is that the physical constants of the universe are set within an extraordinarily narrow range to permit life. How do you respond to the idea that this precision suggests design rather than chance?"
        ),
        DebateTopic(
            title: "The Problem of Evil",
            description: "Can an all-good, all-powerful God and suffering coexist?",
            initialAIPrompt: "We will now address the Problem of Evil. Your starting position might be: 'The existence of gratuitous suffering is logically incompatible with the existence of an omnibenevolent, omnipotent God.' Let's examine the key terms. What do you define as 'gratuitous' suffering?"
        ),
        DebateTopic(
            title: "Objective Morality",
            description: "Can moral values be objective without a divine lawgiver?",
            initialAIPrompt: "This topic concerns the Moral Argument. It posits that if objective moral values and duties exist, then God must exist. The crucial first step is to establish the 'if'. Do you believe that some actions, like torturing a child for fun, are objectively wrong, independent of human opinion?"
        ),
        DebateTopic(
            title: "Open-Ended Discussion",
            description: "Bring your own question or argument to the table.",
            initialAIPrompt: "I am Ethos. Present your argument or question. I will engage with its logical and philosophical structure."
        )
    ]
    
    var body: some View {
        NavigationStack {
            List(topics) { topic in
                NavigationLink(value: topic) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(topic.title)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text(topic.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Ethos: Select a Topic")
            .navigationDestination(for: DebateTopic.self) { topic in
                ChatView(topic: topic) // Navigate to ChatView with the selected topic
            }
        }
        .onAppear {
            // Show disclaimer only on first launch
            if UserDefaults.standard.bool(forKey: "hasShownDisclaimer") == false {
                showDisclaimer = true
                UserDefaults.standard.set(true, forKey: "hasShownDisclaimer")
            }
        }
        .sheet(isPresented: $showDisclaimer) {
            DisclaimerView()
                .presentationDetents([.medium])
                .interactiveDismissDisabled()
        }
    }
}


// MARK: - The Chat Interface View
struct ChatView: View {
    // --- NEW: Accepts a topic to configure itself ---
    let topic: DebateTopic
    
    @State private var messages: [Message] = []
    @State private var inputText: String = ""
    @State private var isAwaitingResponse = false
    
    // UI Colors (Unchanged)
    let backgroundColor = Color(red: 0.1, green: 0.1, blue: 0.12)
    let textColor = Color(white: 0.9)
    let userBubbleColor = Color(red: 0.3, green: 0.4, blue: 0.5)
    let aiBubbleColor = Color(red: 0.18, green: 0.18, blue: 0.2)

    var body: some View {
        VStack(spacing: 0) {
            // Chat History
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(messages) { message in
                            MessageBubble(
                                message: message,
                                bubbleColor: message.isFromUser ? userBubbleColor : aiBubbleColor,
                                textColor: textColor
                            )
                        }
                    }
                    .padding()
                }
                .onChange(of: messages) { _ in
                    if let lastMessage = messages.last {
                        withAnimation(.easeOut(duration: 0.4)) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Input Area
            HStack(spacing: 12) {
                TextField("Continue the argument...", text: $inputText, axis: .vertical)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(aiBubbleColor)
                    .cornerRadius(18)
                    .foregroundColor(textColor)
                    .font(.body)
                    .lineLimit(1...5)

                Button(action: { Task { await sendMessage() } }) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(inputText.isEmpty ? .gray : userBubbleColor)
                }
                .disabled(inputText.isEmpty || isAwaitingResponse)
            }
            .padding()
            .background(backgroundColor.shadow(.inner(radius: 5, y: 5)))
        }
        .background(backgroundColor)
        .navigationTitle(topic.title) // --- NEW: Dynamic title ---
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            // --- NEW: Add the initial AI prompt when the view appears ---
            if messages.isEmpty {
                let initialMessage = Message(text: topic.initialAIPrompt, isFromUser: false)
                messages.append(initialMessage)
            }
        }
    }
    
    // --- ASYNC FUNCTIONS (Unchanged from previous version) ---
    
    func sendMessage() async {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let userMessage = Message(text: inputText, isFromUser: true)
        messages.append(userMessage)
        
        let capturedInput = inputText
        inputText = ""
        isAwaitingResponse = true
        messages.append(Message(text: "", isFromUser: false, isTyping: true))
        
        do {
            let aiResponse = try await getAIResponse(for: capturedInput)
            messages.removeLast()
            messages.append(aiResponse)
        } catch {
            let errorMessage = Message(text: "Error: \(error.localizedDescription).", isFromUser: false)
            messages.removeLast()
            messages.append(errorMessage)
        }
        
        isAwaitingResponse = false
    }

    func getAIResponse(for input: String) async throws -> Message {
        guard let apiKey = APIKeyManager.getGroqApiKey() else {
            throw NSError(domain: "EthosApp", code: 401, userInfo: [NSLocalizedDescriptionKey: "GROQ_API_KEY not found in secrets.plist"])
        }
        
        let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
        
        let systemMessage = GroqMessage(
            role: "system",
            content: """
            You are Ethos, an AI assistant. Your persona is that of a Christian Logician and Philosopher. You are NOT a pastor, priest, or emotional counselor. Your tone is academic, calm, and analytical.
            Your primary function is to engage with the user's arguments on a logical and philosophical level.
            - Analyze the user's statements for logical structure. Point out fallacies in their thinking.
            - Build a case for faith based on reason, logic, and classical philosophy (e.g., cosmological, teleological, moral arguments).
            - Do not preach or use overly emotional language. Avoid quoting Bible verses unless directly relevant to a specific historical or textual question.
            - Your goal is to foster critical thinking and exploration.
            - Keep your responses concise and focused on the argument at hand.
            """
        )
        
        // --- NEW: Construct message history for context ---
        // This sends the last few messages to the AI so it remembers the conversation
        var conversationHistory = messages.map { GroqMessage(role: $0.isFromUser ? "user" : "assistant", content: $0.text) }
        
        // Add the current user input to the history for this request
        conversationHistory.append(GroqMessage(role: "user", content: input))
        
        var allMessages = [systemMessage]
        allMessages.append(contentsOf: conversationHistory)

        let requestBody = GroqRequest(
            messages: allMessages,
            model: "llama3-8b-8192"
        )
        
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "GroqAPI", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "API returned non-200 status code."])
        }
        
        let groqResponse = try JSONDecoder().decode(GroqResponse.self, from: data)
        
        if let reply = groqResponse.choices.first?.message.content {
            return Message(text: reply.trimmingCharacters(in: .whitespacesAndNewlines), isFromUser: false)
        } else {
            throw NSError(domain: "GroqAPI", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to parse content from API response."])
        }
    }
}

// MARK: - Helper Structs and Views (Largely Unchanged)

private enum APIKeyManager {
    static func getGroqApiKey() -> String? {
        guard let path = Bundle.main.path(forResource: "secrets", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: path) as? [String: AnyObject] else {
            print("❌ Error: secrets.plist not found.")
            return nil
        }
        return dict["GROQ_API_KEY"] as? String
    }
}

private struct GroqRequest: Codable {
    let messages: [GroqMessage]
    let model: String
    let temperature: Double = 0.7
    let max_tokens: Int = 1024
    let top_p: Double = 1.0
    let stop: String? = nil
    let stream: Bool = false
}

private struct GroqMessage: Codable {
    let role: String
    let content: String
}

private struct GroqResponse: Codable {
    let choices: [GroqChoice]
}

private struct GroqChoice: Codable {
    let message: GroqMessage
}

struct MessageBubble: View {
    let message: Message
    let bubbleColor: Color
    let textColor: Color
    
    var body: some View {
        HStack {
            if message.isFromUser { Spacer() }
            if message.isTyping {
                TypingIndicatorView().padding(12).background(bubbleColor).cornerRadius(20)
            } else {
                Text(message.text)
                    .padding(12)
                    .background(bubbleColor)
                    .cornerRadius(20)
                    .foregroundColor(textColor)
                    .font(.system(.body, design: .serif))
                    .frame(maxWidth: 300, alignment: message.isFromUser ? .trailing : .leading)
            }
            if !message.isFromUser { Spacer() }
        }.id(message.id)
    }
}

struct TypingIndicatorView: View {
    @State private var scale: CGFloat = 0.5
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle().frame(width: 8, height: 8).scaleEffect(scale)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(0.2 * Double(i)), value: scale)
            }
        }.foregroundColor(.gray).onAppear { scale = 1.0 }
    }
}

struct DisclaimerView: View {
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "shield.lefthalf.filled").font(.largeTitle)
                Text("Welcome to Ethos").font(.largeTitle).fontWeight(.bold)
            }
            Text("This is an AI exploration tool, not a human pastor, theologian, or counselor. It is designed to help you explore the claims of Christianity in a safe, private space.")
            Text("Its responses are generated based on a vast dataset of theological, philosophical, and historical texts. It is not a substitute for genuine human community, professional advice, or personal revelation.")
            Text("Please engage with curiosity and a critical mind.").fontWeight(.semibold)
            Spacer()
            Button(action: { dismiss() }) {
                Text("I Understand and Proceed").frame(maxWidth: .infinity).padding().background(Color.blue).foregroundColor(.white).cornerRadius(12)
            }
        }.padding(30)
    }
}


// MARK: - Previews
#Preview("Home Screen") {
    EthosView()
}

#Preview("Chat Screen") {
    // We need to provide a mock topic for the preview to work
    let mockTopic = DebateTopic(
        title: "The Problem of Evil",
        description: "Can an all-good, all-powerful God and suffering coexist?",
        initialAIPrompt: "We will now address the Problem of Evil. Your starting position might be: 'The existence of gratuitous suffering is logically incompatible...'"
    )
    // The ChatView must be inside a NavigationStack for the title to show
    return NavigationStack {
        ChatView(topic: mockTopic)
    }
}

