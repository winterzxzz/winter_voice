import Foundation

protocol RemoteTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: RemoteTransport {}

struct RemoteTranscriptionProvider: Sendable {
    private struct Response: Decodable { let text: String }
    private let transport: any RemoteTransport

    init(transport: any RemoteTransport = URLSession.shared) { self.transport = transport }

    static func endpoint(for configuration: RemoteProviderConfiguration) throws -> URL {
        _ = try validatedFields(for: configuration)
        let raw = configuration.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: raw), let host = components.host else {
            throw DictationFailure(message: "Enter a valid remote base URL.", recovery: "Use HTTPS, or explicit HTTP for localhost or a LAN address.")
        }
        guard components.user == nil, components.password == nil else {
            throw DictationFailure(message: "Remote URL credentials are not allowed.", recovery: "Store API credentials in Keychain instead.")
        }
        guard components.fragment == nil else {
            throw DictationFailure(message: "Remote URL fragments are not allowed.", recovery: "Remove the fragment and try again.")
        }
        let isHTTPS = components.scheme?.lowercased() == "https"
        let isHTTP = components.scheme?.lowercased() == "http"
        guard isHTTPS || (isHTTP && isLocalOrLAN(host)) else {
            throw DictationFailure(message: "That remote URL is not allowed.", recovery: "Use HTTPS. HTTP is allowed only for explicit localhost or LAN endpoints.")
        }
        var path = components.path
        if path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix("/audio/transcriptions") { path += "/audio/transcriptions" }
        components.path = path
        guard let endpoint = components.url else {
            throw DictationFailure(message: "Enter a valid remote base URL.", recovery: "Check the URL and try again.")
        }
        return endpoint
    }

    func transcribe(
        audio: RecordedAudio,
        configuration: RemoteProviderConfiguration,
        apiKey: String?
    ) async throws -> String {
        let endpoint = try Self.endpoint(for: configuration)
        let request = try Self.makeRequest(
            endpoint: endpoint,
            audio: audio,
            configuration: configuration,
            apiKey: apiKey,
            boundary: "WinterVoice-\(UUID().uuidString)"
        )
        let data: Data
        let response: URLResponse
        do { (data, response) = try await transport.data(for: request) } catch {
            throw DictationFailure(message: "Could not reach the remote provider.", recovery: "Check the endpoint and network connection.")
        }
        return try Self.decode(data: data, response: response)
    }

    static func makeRequest(
        endpoint: URL,
        audio: RecordedAudio,
        configuration: RemoteProviderConfiguration,
        apiKey: String?,
        boundary: String
    ) throws -> URLRequest {
        let fields = try validatedFields(for: configuration)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        if let apiKey, !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = MultipartAudioBody.make(
            audio: audio,
            model: fields.model,
            language: fields.language,
            boundary: boundary
        )
        return request
    }

    private static func validatedFields(
        for configuration: RemoteProviderConfiguration
    ) throws -> (model: String, language: String?) {
        guard !containsLineBreak(configuration.model) else {
            throw DictationFailure(message: "Remote model contains an invalid line break.", recovery: "Remove line breaks and try again.")
        }
        let model = configuration.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            throw DictationFailure(message: "Enter a remote model name.", recovery: "Use the model identifier expected by your endpoint.")
        }
        guard !containsLineBreak(configuration.language) else {
            throw DictationFailure(message: "Remote language contains an invalid line break.", recovery: "Remove line breaks and try again.")
        }
        let language = configuration.normalizedLanguage
        return (model, language)
    }

    private static func containsLineBreak(_ value: String) -> Bool {
        value.unicodeScalars.contains { $0.value == 0x0D || $0.value == 0x0A }
    }

    static func decode(data: Data, response: URLResponse) throws -> String {
        guard let http = response as? HTTPURLResponse else {
            throw DictationFailure(message: "The remote provider returned an invalid response.", recovery: "Check provider compatibility.")
        }
        switch http.statusCode {
        case 200..<300: break
        case 401, 403:
            throw DictationFailure(message: "Remote authentication failed.", recovery: "Check the API key stored in Keychain.")
        case 404:
            throw DictationFailure(message: "Remote transcription endpoint was not found.", recovery: "Check the base URL.")
        default:
            throw DictationFailure(message: "Remote transcription failed (HTTP \(http.statusCode)).", recovery: "Check the provider configuration and try again.")
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data), !decoded.text.isEmpty else {
            throw DictationFailure(message: "The remote provider returned an invalid response.", recovery: "Expected an OpenAI-compatible JSON response containing text.")
        }
        return decoded.text
    }

    private static func isLocalOrLAN(_ host: String) -> Bool {
        if host == "localhost" || host == "::1" || host.hasSuffix(".local") { return true }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4 else { return false }
        return octets[0] == 10
            || (octets[0] == 192 && octets[1] == 168)
            || (octets[0] == 172 && (16...31).contains(octets[1]))
            || octets[0] == 127
    }
}

private enum MultipartAudioBody {
    static func make(audio: RecordedAudio, model: String, language: String?, boundary: String) -> Data {
        var body = Data()
        func append(_ value: String) { body.append(Data(value.utf8)) }
        func field(_ name: String, _ value: String) {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        field("model", model)
        if let language { field("language", language) }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n")
        body.append(wavData(audio))
        append("\r\n--\(boundary)--\r\n")
        return body
    }

    private static func wavData(_ audio: RecordedAudio) -> Data {
        let sampleData = audio.samples.withUnsafeBytes { Data($0) }
        var data = Data()
        func ascii(_ value: String) { data.append(Data(value.utf8)) }
        func le<T: FixedWidthInteger>(_ value: T) { var value = value.littleEndian; data.append(Data(bytes: &value, count: MemoryLayout<T>.size)) }
        ascii("RIFF"); le(UInt32(36 + sampleData.count)); ascii("WAVEfmt "); le(UInt32(16)); le(UInt16(3)); le(UInt16(1))
        le(UInt32(audio.sampleRate)); le(UInt32(audio.sampleRate * 4)); le(UInt16(4)); le(UInt16(32)); ascii("data"); le(UInt32(sampleData.count)); data.append(sampleData)
        return data
    }
}
