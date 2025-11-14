import mysql.connector
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from config.config import ServiceType
# from mysql.connector import Error


class MariaDBCheck:
    """MariaDB/Galera cluster health monitoring"""

    def __init__(self, config, debug=False):
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

    def run_check(self):
        """Execute MariaDB/Galera cluster health check"""
        start_time = time.time()

        if self.debug:
            print(f"🔧 [MARIADB_DEBUG] Starting cluster health check for {len(self.nodes)} nodes")

        try:
            # 1. Check all nodes in parallel
            cluster_status = self._check_galera_cluster()

            # 2. Calculate reachable nodes count
            reachable_count = len(cluster_status['reachable_nodes'])
            total_count = len(self.nodes)

            if self.debug:
                print(f"🔧 [MARIADB_DEBUG] Nodes: {reachable_count}/{total_count} reachable")
                print(f"🔧 [MARIADB_DEBUG] Reachable: {cluster_status['reachable_nodes']}")
                print(f"🔧 [MARIADB_DEBUG] Unreachable: {cluster_status['unreachable_nodes']}")

            # 3. Determine overall status
            if reachable_count == total_count:
                cluster_healthy = self._determine_cluster_status(cluster_status)
                if self.debug:
                    print(f"🔧 [MARIADB_DEBUG] All nodes reachable, cluster healthy: {cluster_healthy}")
                status = 'OK' if cluster_healthy else 'DEGRADED'
            elif reachable_count > 0:
                if self.debug:
                    print(f"🔧 [MARIADB_DEBUG] Some nodes unreachable, cluster degraded")
                status = 'DEGRADED'
            else:
                if self.debug:
                    print(f"🔧 [MARIADB_DEBUG] All nodes unreachable, cluster error")
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
            if self.debug:
                print(f"🔧 [MARIADB_DEBUG] Check failed with error: {str(e)}")
            return {
                'status': 'ERROR',
                'response_time': round(time.time() - start_time, 2),
                'error': str(e)
            }

    def _check_galera_cluster(self):
        """Check entire Galera cluster using parallel connections"""
        status = {
            'reachable_nodes': [],
            'unreachable_nodes': [],
            'node_details': {}
        }

        # 1. Create list of node checking tasks
        node_tasks = [
            (display_name, connect_host)
            for display_name, connect_host in self.nodes
        ]

        if self.debug:
            print(f"🔧 [MARIADB_DEBUG] Starting parallel checks for {len(node_tasks)} nodes")

        # 2. Execute parallel checks with ThreadPoolExecutor
        max_workers = min(5, len(node_tasks))
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            # Submit all node checking tasks
            future_to_node = {
                executor.submit(self._check_single_node, display_name, connect_host):
                    (display_name, connect_host)
                for display_name, connect_host in node_tasks
            }

            # 3. Process results as they complete
            for future in as_completed(future_to_node):
                display_name, connect_host = future_to_node[future]

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
                        if self.debug:
                            print(
                                f"🔧 [MARIADB_DEBUG] ✗ {display_name} is unreachable: {node_result.get('error', 'Unknown error')}")

                except Exception as e:
                    status['unreachable_nodes'].append(display_name)
                    if self.debug:
                        print(f"🔧 [MARIADB_DEBUG] ✗ {display_name} failed with exception: {str(e)}")

        if self.debug:
            print(
                f"🔧 [MARIADB_DEBUG] Cluster check completed: {len(status['reachable_nodes'])} reachable, {len(status['unreachable_nodes'])} unreachable")

        return status

    def _check_single_node(self, display_name, connect_host):
        """Check health of single MariaDB node"""
        try:
            if self.debug:
                print(f"🔧 [MARIADB_DEBUG] Connecting to {display_name} at {connect_host}")

            start_time = time.time()

            connection = mysql.connector.connect(
                host=connect_host,
                **self.db_config,
                connection_timeout=10
            )

            # 2. Execute Galera status query
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

            # 3. Parse metrics into structured format
            metrics = self._parse_galera_metrics(results)

            if self.debug:
                print(f"🔧 [MARIADB_DEBUG] {display_name} connected successfully in {response_time:.3f}s")
                print(f"🔧 [MARIADB_DEBUG] {display_name} metrics: {metrics}")

            return {
                'reachable': True,
                'response_time': round(response_time, 3),
                'metrics': metrics
            }

        except Exception as e:
            if self.debug:
                print(f"🔧 [MARIADB_DEBUG] {display_name} connection failed: {str(e)}")
            return {
                'reachable': False,
                'error': str(e)
            }

    def _parse_galera_metrics(self, results):
        """
        Parse SHOW GLOBAL STATUS results into structured Galera metrics

        Args:
            results: List of tuples from cursor.fetchall() - [('Variable_name', 'Value'), ...]

        Returns:
            Dictionary with parsed Galera metrics
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
        Determine overall cluster health based on Galera-specific criteria

        Args:
            cluster_status: Result from _check_galera_cluster()

        Returns:
            Boolean - True if cluster is healthy, False if degraded
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

        # Check each reachable node for Galera health criteria
        healthy_nodes = 0

        for node_name in reachable_nodes:
            node_details = cluster_status['node_details'][node_name]
            metrics = node_details['metrics']

            # Galera health criteria:
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

        # Cluster is healthy if majority of nodes are healthy
        # (Galera requires quorum - typically majority of nodes)
        quorum_healthy = healthy_nodes >= (expected_cluster_size // 2 + 1)

        if self.debug:
            print(
                f"🔧 [MARIADB_DEBUG] Cluster health: {healthy_nodes}/{len(reachable_nodes)} healthy nodes, quorum: {quorum_healthy}")

        return quorum_healthy