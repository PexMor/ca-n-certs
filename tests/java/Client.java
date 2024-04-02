
// Implicit package to be used in jshell etc.
import javax.net.ssl.*;
import java.net.URI;
import java.io.FileInputStream;
import java.security.KeyStore;
import java.security.cert.CertificateFactory;
import java.security.cert.X509Certificate;

/*
 * Test this with `jshell` or `CA_CERT="" jshell` or `CA_CERT="path/to/ca.pem" jshell`
 * /open Client.java
 * Client.main(new String[0])
 * ---
 * javac Client.java
 * java -classpath . Client https://example:4545/dfdf
 */
// SSL/TLS Client
public class Client {
    public static void main(String[] args) throws Exception {
        // get value of environment variable or default
        String host = System.getenv("HOST") != null ? System.getenv("HOST") : "localhost";
        String port_str = System.getenv("PORT") != null ? System.getenv("PORT") : "8443";

        // print first argument provided at command line
        if (args.length > 0) {
            // https://server:port/path
            System.out.println(args[0]);
            // parse the URL into host, port, and path
            URI urlParsed = new URI(args[0]);
            // print the host, port, and path
            System.out.println("Scheme: " + urlParsed.getScheme() + " Host: " + urlParsed.getHost() + " Port: "
                    + urlParsed.getPort()
                    + " Path: " + urlParsed.getPath());
            host = urlParsed.getHost();
            if (urlParsed.getPort() == -1) {
                if (urlParsed.getScheme().equals("https")) {
                    port_str = "443";
                } else {
                    port_str = "80";
                }
            } else {
                port_str = Integer.toString(urlParsed.getPort());
            }
        }
        String javaHome = System.getenv("JAVA_HOME") != null ? System.getenv("JAVA_HOME")
                : System.getProperty("java.home");
        // print java home
        System.out.println("Java Home: " + javaHome);
        // print lib/security/cacerts
        String cacerts = javaHome + "/lib/security/cacerts";
        System.out.println("Java lib/security/cacerts: " + cacerts);
        // Load the custom CA certificate
        String home = System.getenv("HOME") != null ? System.getenv("HOME") : "/tmp";
        // DEF_BD = os.path.join(os.getenv("HOME", "/tmp"), ".config", "demo-ssl")
        String defBaseDir = home + "/.config/demo-ssl";
        String caCertDefPath = defBaseDir + "/ca.pem";
        String caCertPath = System.getenv("CA_CERT") != null ? System.getenv("CA_CERT") : caCertDefPath;
        boolean exists = new java.io.File(caCertPath).exists();
        SSLContext sslContext = SSLContext.getInstance("TLS");
        if (exists) {
            System.out.println("CA certificate exists: " + caCertPath);
            KeyStore trustStore = KeyStore.getInstance(KeyStore.getDefaultType());
            trustStore.load(null, null);
            CertificateFactory certificateFactory = CertificateFactory.getInstance("X.509");

            FileInputStream caCertInputStream = new FileInputStream(caCertPath);
            X509Certificate caCert = (X509Certificate) certificateFactory.generateCertificate(caCertInputStream);
            trustStore.setCertificateEntry("custom_ca", caCert);

            // Create a TrustManager that trusts the custom CA certificate
            TrustManagerFactory trustManagerFactory = TrustManagerFactory
                    .getInstance(TrustManagerFactory.getDefaultAlgorithm());
            trustManagerFactory.init(trustStore);
            TrustManager[] trustManagers = trustManagerFactory.getTrustManagers();
            // Create an SSLContext with the custom TrustManager
            sslContext.init(null, trustManagers, null);
        } else {
            System.out.println("CA certificate does not exist");
            sslContext.init(null, null, null);
        }

        // Create an SSLSocketFactory from the SSLContext
        SSLSocketFactory sslSocketFactory = sslContext.getSocketFactory();

        int serverPort = Integer.parseInt(port_str);
        // print the host and port
        System.out.println("Host: " + host + " Port: " + serverPort);
        // Connect to the TLS server
        try {
            SSLSocket sslSocket = (SSLSocket) sslSocketFactory.createSocket(host, serverPort);

            // build the string to send sprintf
            String httpReq = "GET / HTTP/1.1\r\nHost: " + host + "\r\n\r\n";
            sslSocket.getOutputStream().write(httpReq.getBytes());
            byte[] buffer = new byte[1024];
            int bytesRead = sslSocket.getInputStream().read(buffer);
            System.out.println(new String(buffer, 0, bytesRead));

            // Close the SSL socket
            sslSocket.close();

        } catch (Exception e) {
            System.out.println("Error: " + e.getMessage());
        }
    }
}
