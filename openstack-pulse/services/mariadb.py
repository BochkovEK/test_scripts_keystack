"""
MariaDB/Galera Cluster monitoring
Checks cluster health, node synchronization and replication status
"""

import mysql.connector
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from config.config import ServiceType


class MariaDBCheck:
    """
    MariaDB/Galera Cluster health monitoring class.

    Provides comprehensive monitoring of MariaDB Galera clusters including:
    - Node connectivity and response times
    - Cluster synchronization status
    - Node readiness and connectivity
    - Quorum and cluster health determination
    - Parallel health checks across all cluster nodes
    """

    def __init__(self, config, debug=False):
        """
        Initialize MariaDB health check.

        Args:
            config: Config object providing service authentication
            debug: Enable debug output for troubleshooting
        """
        self.config = config
        self.debug = debug
        auth_params = config.get_service_auth(ServiceType.MARIADB)

        if self.debug:
            print(f"🔧 [MARIADB_DEBUG] Initialized with {len(auth_params['nodes'])} nodes")
            print(f"🔧 [MARIADB_DEBUG] Auth: user={auth_params['username']}, port={auth_params.get('port', 3306)}")

        # Database connection parameters
        self.db_config = {
            'user': auth_params['username'],
            'password': auth_params['password'],
            'port': auth_params.get('port', 3306),
            'connect_timeout': 3
        }
        self.nodes = auth_params['nodes']  # [display_name, connect_host]

    def display_details(self, data):
        """
        Display MariaDB/Galera cluster health details in formatted output.

        Args:
            data: Dictionary containing cluster status and node information
        """
        cluster = data['cluster']
        total_nodes = data['total_nodes']
        reachable_nodes = data['reachable_nodes']

        # Display nodes summary
        print(f"  Nodes: {reachable_nodes}/{total_nodes} reachable")

        # Display unreachable nodes with detailed error information
        if cluster.get('cluster_errors'):
            for error in cluster['cluster_errors']:
                # Extract node name and error message from formatted error string
                node_name = error.split(':')[0] if ':' in error else error
                error_message = error.split(':', 1)[1] if ':' in error else error
                print(f"    ❌ {node_name}: {error_message.strip()}")
                print(f"      Status: Unknown")

        # Display detailed status for each reachable node
        for node_name, details in cluster['node_details'].items():
            response_time = details.get('response_time', '?')
            metrics = details.get('metrics', {})

            print(f"    🟢 ({response_time}s) {node_name}:")

            # Display Galera cluster specific metrics
            cluster_status = metrics.get('cluster_status', 'Unknown')
            cluster_size = metrics.get('cluster_size', 0)
            local_state = metrics.get('local_state', 'Unknown')

            print(f"      Status: {local_state}, "
                  f"Cluster: {cluster_status} "
                  f"({cluster_size} nodes)")

            # Display node operational status
            node_ready = 'ON' if metrics.get('node_ready') else 'OFF'
            connected = 'ON' if metrics.get('connected') else 'OFF'
            print(f"      Ready: {node_ready}, Connected: {connected}")

    def run_check(self):
        """
        Execute comprehensive MariaDB/Galera cluster health check.

        Returns:
            Dictionary containing:
            - status: Overall cluster status ('OK', 'DEGRADED', 'ERROR')
            - response_time: Total check execution time
            - cluster: Detailed cluster status information
            - reachable_nodes: Count of reachable nodes
            - total_nodes: Total number of configured nodes
        """
        start_time = time.time()

        if self.debug:
            print(f"🔧 [MARIADB_DEBUG] Starting cluster health check for {len(self.nodes)} nodes")

        try:
            cluster_status = self._check_galera_cluster()

            # Calculate node reachability statistics
            reachable_count = len(cluster_status['reachable_nodes'])
            total_count = len(self.nodes)

            if self.debug:
                print(f"🔧 [MARIADB_DEBUG] Cluster status: {reachable_count}/{total_count} nodes reachable")

            # Handle complete cluster unreachable scenario
            if reachable_count == 0 and cluster_status.get('cluster_errors'):
                main_error = cluster_status['cluster_errors'][0]
                if self.debug:
                    print(f"🔧 [MARIADB_DEBUG] All nodes unreachable, using error: {main_error}")

                return {
                    'status': 'ERROR',
                    'response_time': round(time.time() - start_time, 2),
                    'error': main_error,
                    'cluster': cluster_status,
                    'reachable_nodes': reachable_count,
                    'total_nodes': total_count
                }

            # Determine overall cluster status based on node availability and health
            if reachable_count == total_count:
                cluster_healthy = self._determine_cluster_status(cluster_status)
                status = 'OK' if cluster_healthy else 'DEGRADED'
            elif reachable_count > 0:
                status = 'DEGRADED'
            else:
                status = 'ERROR'

            result = {
                'status': status,
                'response_time': round(time.time() - start_time, 2),
                'cluster': cluster_status,
                'reachable_nodes': reachable_count,
                'total_nodes': total_count
            }

            if self.debug:
                print(f"🔧 [MARIADB_DEBUG] Check completed in {result['response_time']}s, status: {status}")

            return result

        except Exception as e:
            error_message = str(e)

            # Map common MySQL connection errors to user-friendly messages
            if "access denied" in error_message.lower() or "1045" in error_message:
                error_message = "Access denied - check MySQL credentials"
            elif "can't connect" in error_message.lower() or "2003" in error_message:
                error_message = "Connection refused - check host/port"
            elif "timeout" in error_message.lower():
                error_message = "Connection timeout - check network connectivity"

            if self.debug:
                print(f"🔧 [MARIADB_DEBUG] Check failed with error: {error_message}")

            return {
                'status': 'ERROR',
                'response_time': round(time.time() - start_time, 2),
                'error': error_message
            }

    def _check_galera_cluster(self):
        """
        Perform parallel health checks across all Galera cluster nodes.

        Returns:
            Dictionary containing:
            - reachable_nodes: List of reachable node names
            - unreachable_nodes: List of unreachable node names
            - node_details: Detailed metrics for each reachable node
            - cluster_errors: Aggregated error messages for unreachable nodes
        """
        status = {
            'reachable_nodes': [],
            'unreachable_nodes': [],
            'node_details': {},
            'cluster_errors': []  # Collect all errors for aggregated display
        }

        # Configure thread pool for parallel node checks
        max_workers = min(5, len(self.nodes))

        if self.debug:
            print(f"🔧 [MARIADB_DEBUG] Starting cluster check with {max_workers} workers")

        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            # Submit node check tasks to thread pool
            future_to_info = {
                executor.submit(self._check_single_node, display_name, connect_host):
                    (display_name, connect_host)
                for display_name, connect_host in self.nodes
            }

            # Process completed node checks as they finish
            for future in as_completed(future_to_info):
                display_name, connect_host = future_to_info[future]
                try:
                    node_result = future.result()

                    if node_result['reachable']:
                        status['reachable_nodes'].append(display_name)
                        status['node_details'][display_name] = {
                            'response_time': node_result['response_time'],
                            'metrics': node_result['metrics']
                        }
                        if self.debug:
                            print(f"🔧 [MARIADB_DEBUG] ✓ {display_name} is reachable")
                    else:
                        status['unreachable_nodes'].append(display_name)
                        error_msg = node_result.get('error', 'Unknown error')
                        status['cluster_errors'].append(f"{display_name}: {error_msg}")
                        if self.debug:
                            print(f"🔧 [MARIADB_DEBUG] ✗ {display_name} is unreachable: {error_msg}")
                except Exception as e:
                    status['unreachable_nodes'].append(display_name)
                    error_msg = f"Exception: {str(e)}"
                    status['cluster_errors'].append(f"{display_name}: {error_msg}")
                    if self.debug:
                        print(f"🔧 [MARIADB_DEBUG] ✗ {display_name} failed with exception: {error_msg}")

        if self.debug:
            print(f"🔧 [MARIADB_DEBUG] Cluster check completed: {len(status['reachable_nodes'])} reachable, {len(status['unreachable_nodes'])} unreachable")

        return status

    def _check_single_node(self, display_name, connect_host):
        """
        Perform health check on a single MariaDB node.

        Args:
            display_name: Human-readable node identifier
            connect_host: Network address for connection

        Returns:
            Dictionary containing reachability status and node metrics
        """

        if self.debug:
            current_port = self.db_config.get('port', 3306)
            print(f"🔧 [MARIADB_DEBUG] Connecting to node '{display_name}' via endpoint: {connect_host}:{current_port}")

        try:
            if self.debug:
                print(f"🔧 [MARIADB_DEBUG] Checking node {display_name} at {connect_host}")

            start_time = time.time()

            # Establish database connection
            connection = mysql.connector.connect(
                host=connect_host,
                **self.db_config,
                connection_timeout=10
            )

            # Execute Galera status query
            with connection.cursor() as cursor:
                cursor.execute("""
                    SHOW GLOBAL STATUS WHERE Variable_name IN (
                        'wsrep_cluster_status',
                        'wsrep_cluster_size', 
                        'wsrep_ready',
                        'wsrep_local_state_comment',
                        'wsrep_connected'
                    )
                """)
                results = cursor.fetchall()

            response_time = time.time() - start_time
            connection.close()

            # Parse query results into structured metrics
            metrics = self._parse_galera_metrics(results)

            if self.debug:
                print(f"🔧 [MARIADB_DEBUG] {display_name} responded in {response_time:.3f}s")
                print(f"🔧 [MARIADB_DEBUG] {display_name} metrics: {metrics}")

            return {
                'reachable': True,
                'response_time': round(response_time, 3),
                'metrics': metrics
            }

        except mysql.connector.Error as e:
            error_msg = str(e)
            # Map MySQL error codes to descriptive messages
            if e.errno == 1045:
                error_msg = "Access denied for user - check credentials"
            elif e.errno == 2003:
                error_msg = "Can't connect to MySQL server - check host/port"
            elif e.errno == 2006:
                error_msg = "MySQL server has gone away"
            elif "timeout" in error_msg.lower():
                error_msg = "Connection timeout - server not responding"

            if self.debug:
                print(f"🔧 [MARIADB_DEBUG] {display_name} connection failed: {error_msg}")

            return {
                'reachable': False,
                'error': error_msg
            }
        except Exception as e:
            error_msg = str(e)
            if self.debug:
                print(f"🔧 [MARIADB_DEBUG] {display_name} connection failed: {error_msg}")
            return {
                'reachable': False,
                'error': error_msg
            }

    def _parse_galera_metrics(self, results):
        """
        Parse SHOW GLOBAL STATUS results into structured Galera metrics.

        Args:
            results: List of tuples from cursor.fetchall() - [('Variable_name', 'Value'), ...]

        Returns:
            Dictionary with parsed Galera cluster metrics
        """
        # Convert list of tuples to dictionary for easy lookup
        metrics_dict = {row[0]: row[1] for row in results}

        metrics = {
            'cluster_status': metrics_dict.get('wsrep_cluster_status', 'Unknown'),
            'cluster_size': int(metrics_dict.get('wsrep_cluster_size', 0)),
            'node_ready': metrics_dict.get('wsrep_ready', 'OFF') == 'ON',
            'local_state': metrics_dict.get('wsrep_local_state_comment', 'Unknown'),
            'connected': metrics_dict.get('wsrep_connected', 'OFF') == 'ON'
        }

        if self.debug:
            print(f"🔧 [MARIADB_DEBUG] Parsed metrics: {metrics}")

        return metrics

    def _determine_cluster_status(self, cluster_status):
        """
        Determine overall cluster health based on Galera-specific criteria.

        Implements quorum-based health determination requiring majority of nodes
        to be healthy for cluster to be considered operational.

        Args:
            cluster_status: Result from _check_galera_cluster()

        Returns:
            Boolean - True if cluster meets quorum and health criteria, False otherwise
        """
        reachable_nodes = cluster_status['reachable_nodes']

        # If no nodes reachable, cluster is not healthy
        if not reachable_nodes:
            if self.debug:
                print(f"🔧 [MARIADB_DEBUG] No reachable nodes, cluster unhealthy")
            return False

        expected_cluster_size = len(self.nodes)
        if self.debug:
            print(f"🔧 [MARIADB_DEBUG] Checking cluster health, expected size: {expected_cluster_size}")

        # Evaluate each reachable node against Galera health criteria
        healthy_nodes = 0

        for node_name in reachable_nodes:
            node_details = cluster_status['node_details'][node_name]
            metrics = node_details['metrics']

            # Galera health criteria for a node:
            is_healthy = (
                metrics.get('cluster_status') == 'Primary' and
                metrics.get('node_ready') is True and
                metrics.get('connected') is True and
                metrics.get('local_state') == 'Synced' and
                metrics.get('cluster_size') == expected_cluster_size
            )

            if is_healthy:
                healthy_nodes += 1
                if self.debug:
                    print(f"🔧 [MARIADB_DEBUG] ✓ {node_name} is healthy")
            else:
                if self.debug:
                    print(f"🔧 [MARIADB_DEBUG] ✗ {node_name} is unhealthy: {metrics}")

        # Galera requires quorum - typically majority of nodes must be healthy
        quorum_healthy = healthy_nodes >= (expected_cluster_size // 2 + 1)

        if self.debug:
            print(f"🔧 [MARIADB_DEBUG] Cluster health: {healthy_nodes}/{len(reachable_nodes)} healthy nodes, quorum: {quorum_healthy}")

        return quorum_healthy

    def close_sessions(self):
        """Close database connections and cleanup resources."""
        # MySQL connector connections are closed after each query
        # No persistent sessions to close in this implementation
        if self.debug:
            print(f"🔧 [MARIADB_DEBUG] No persistent sessions to close")

