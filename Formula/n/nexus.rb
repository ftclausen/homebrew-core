class Nexus < Formula
  desc "Repository manager for binary software components"
  homepage "https://www.sonatype.com/"
  url "https://github.com/sonatype/nexus-public.git",
      tag:      "release-3.81.0-08",
      revision: "c8ccb46ff257048524efef50b9abcc077e98096f"
  license "EPL-1.0"

  # As of writing, upstream is publishing both v2 and v3 releases. The "latest"
  # release on GitHub isn't reliable, as it can point to a release from either
  # one of these major versions depending on which was published most recently.
  livecheck do
    url :stable
    regex(/^(?:release[._-])?v?(\d+(?:[.-]\d+)+)$/i)
  end

  no_autobump! because: :requires_manual_review

  bottle do
    sha256 cellar: :any_skip_relocation, arm64_sequoia: "c8a3fd80c8008fd25205fb318ee06ae801a7d74d969b1d6f06bf5e7c2fb62b4c"
    sha256 cellar: :any_skip_relocation, arm64_sonoma:  "41d2feb6e85f4df82192cf62afdb21e93bf5ea79b8fc163f9d297d4a440f8c39"
    sha256 cellar: :any_skip_relocation, arm64_ventura: "939834966728216f77cd05f37e7be1d40e803615792cbc94510880e22be58514"
    sha256 cellar: :any_skip_relocation, sonoma:        "b368f0bd961164f00b33c38de70810cf24091f457dcfaf96bcbf41ac10102df9"
    sha256 cellar: :any_skip_relocation, ventura:       "1317def65ab1ab74b617e15c16918e3d1eed2bd974007049d942d96ced029a7c"
    sha256 cellar: :any_skip_relocation, arm64_linux:   "8bd720dbef91a776d339d8a3dfd14a4f960a01a40f9388a5503c1c285da8f8be"
    sha256 cellar: :any_skip_relocation, x86_64_linux:  "d5dae4e536f76bf9badb1b6989d8d2a671009767a8324f16b81748471d6fdf2a"
  end

  depends_on "maven" => :build
  depends_on "node" => :build
  depends_on "yarn" => :build
  depends_on "openjdk@17"

  uses_from_macos "unzip" => :build

  # Use corepack to install yarn
  # Fix repo creation UI errors so repos can actually be managed
  patch :DATA

  def install
    # Workaround build error: Couldn't find package "@sonatype/nexus-ui-plugin@workspace:*"
    # Ref: https://github.com/sonatype/nexus-public/issues/417
    # Ref: https://github.com/sonatype/nexus-public/issues/432#issuecomment-2663250153
    inreplace ["plugins/nexus-coreui-plugin/package.json"],
              '"@sonatype/nexus-ui-plugin": "workspace:*"',
              '"@sonatype/nexus-ui-plugin": "*"'

    java_version = "17"
    ENV["JAVA_HOME"] = Language::Java.java_home(java_version)
    java_env = Language::Java.overridable_java_home_env(java_version)
    java_env.merge!(KARAF_DATA: "${NEXUS_KARAF_DATA:-#{var}/nexus}",
                    KARAF_LOG:  var/"log/nexus",
                    KARAF_ETC:  pkgetc)

    system "./mvnw", "install", "-DskipTests", "-Dpublic"

    assembly = "assemblies/nexus-repository-core/target/assembly"
    rm(Dir["#{assembly}/bin/*.bat"])
    libexec.install Dir["#{assembly}/*"]
    chmod "+x", Dir["#{libexec}/bin/*"]
    (bin/"nexus").write_env_script libexec/"bin/nexus", java_env
  end

  def post_install
    (var/"log/nexus").mkpath unless (var/"log/nexus").exist?
    (var/"nexus").mkpath unless (var/"nexus").exist?
    pkgetc.mkpath unless pkgetc.exist?
  end

  service do
    run [opt_bin/"nexus", "start"]
  end

  test do
    port = free_port
    (testpath/"data/etc/nexus.properties").write "application-port=#{port}"
    pid = spawn({ "NEXUS_KARAF_DATA" => testpath/"data" }, bin/"nexus", "server")
    sleep 50
    sleep 50 if OS.mac? && Hardware::CPU.intel?
    assert_match "<title>Sonatype Nexus Repository</title>", shell_output("curl --silent --fail http://localhost:#{port}")
  ensure
    Process.kill "TERM", pid
    Process.wait pid
  end
end

__END__
diff --git a/pom.xml b/pom.xml
index aaa8182482b..bacc2277195 100644
--- a/pom.xml
+++ b/pom.xml
@@ -69,9 +69,9 @@
 
     <!-- Define the node and yarn versions used by the frontend-maven-plugin -->
     <node.version>v18.17.1</node.version>
-    <yarn.version>v1.22.19</yarn.version>
+    <yarn.version>v3.2.3</yarn.version>
     <npm.install>install --immutable</npm.install>
-    <npm.skipTests>false</npm.skipTests>
+    <npm.skipTests>true</npm.skipTests>
     <npm.build>build-all</npm.build>
 
     <!-- logging configuration used in logback config files to control test logging -->
@@ -702,7 +702,7 @@
         <plugin>
           <groupId>com.github.eirslett</groupId>
           <artifactId>frontend-maven-plugin</artifactId>
-          <version>1.11.3</version>
+          <version>1.15.1</version>
 
           <configuration>
             <nodeVersion>${node.version}</nodeVersion>
@@ -717,30 +717,31 @@
 
           <executions>
             <execution>
-              <id>install node and yarn</id>
+              <id>install node and corepack</id>
               <goals>
-                <goal>install-node-and-yarn</goal>
+                <goal>install-node-and-corepack</goal>
               </goals>
               <phase>generate-resources</phase>
             </execution>
+
             <execution>
               <id>yarn install</id>
               <goals>
-                <goal>yarn</goal>
+                <goal>corepack</goal>
               </goals>
               <phase>generate-resources</phase>
               <configuration>
-                <arguments>${npm.install}</arguments>
+                <arguments>yarn install --no-immutable</arguments>
               </configuration>
             </execution>
             <execution>
               <id>yarn run build</id>
               <goals>
-                <goal>yarn</goal>
+                <goal>corepack</goal>
               </goals>
               <phase>compile</phase>
               <configuration>
-                <arguments>${npm.build}</arguments>
+                <arguments>yarn run build</arguments>
               </configuration>
             </execution>
           </executions>
diff --git a/plugins/nexus-coreui-plugin/src/main/resources/static/rapture/NX/coreui/controller/Repositories.js b/plugins/nexus-coreui-plugin/src/main/resources/static/rapture/NX/coreui/controller/Repositories.js
index d570932ebb5..fedbbb6015d 100644
--- a/plugins/nexus-coreui-plugin/src/main/resources/static/rapture/NX/coreui/controller/Repositories.js
+++ b/plugins/nexus-coreui-plugin/src/main/resources/static/rapture/NX/coreui/controller/Repositories.js
@@ -723,7 +723,15 @@ Ext.define('NX.coreui.controller.Repositories', {
     });
   },
 
+  isCoreEdition: function() {
+    return NX.State.getEdition() === 'CORE';
+  },
+
   checkFirewallCapabilitiesStatus: function(repositoryName, callback) {
+    if (this.isCoreEdition()) {
+      return;
+    }
+
     NX.direct.firewall_RepositoryStatus.readCapabilitiesStatus(repositoryName, function (response) {
       if (Ext.isObject(response) && response.success && response.data != null) {
         callback(response.data === true);
@@ -734,6 +742,10 @@ Ext.define('NX.coreui.controller.Repositories', {
   },
 
   checkFirewallCapabilitiesStatusForPypi: function(repositoryName, callback) {
+    if (this.isCoreEdition()) {
+      return;
+    }
+
     NX.direct.firewall_RepositoryStatus.readCapabilitiesStatus(repositoryName, function (response) {
       if (Ext.isObject(response) && response.success && response.data != null) {
         callback(response.data === true);

