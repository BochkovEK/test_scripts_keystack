import mysql.connector
from mysql.connector import Error
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from config.config import ServiceType


class MariaDBCheck:
    """MariaDB/Galera cluster health monitoring"""

    def __init__(self, config):
        self.config = config
        auth_params = config.get_service_auth(ServiceType.MARIADB)

        # Database connection parameters
        self.db_config = {
            'user': auth_params['username'],
            'password': auth_params['password'],
            'port': auth_params.get('port', 3306),
            'connect_timeout': 3
        }
        self.nodes = auth_params['nodes']  # [display_name, connect_host]

    # def run_check(self):
    #     """Execute MariaDB/Galera cluster health check"""
    #     start_time = time.time()
    #
    #     try:
    #         # 1. Check all nodes in parallel
    #         cluster_status = self._check_galera_cluster()
    #
    #         # 2. Calculate reachable nodes count
    #         reachable_count = len(cluster_status['reachable_nodes'])
    #         total_count = len(self.nodes)
    #
    #         # 3. Determine overall status based on Galera-specific criteria
    #         if reachable_count == total_count:
    #             # All nodes reachable - check Galera cluster health
    #             if self._determine_cluster_status(cluster_status):
    #                 status = 'OK'
    #             else:
    #                 status = 'DEGRADED'
    #         elif reachable_count > 0:
    #             status = 'DEGRADED'  # Some nodes unreachable
    #         else:
    #             status = 'ERROR'  # All nodes unreachable
    #
    #         return {
    #             'status': status,
    #             'response_time': round(time.time() - start_time, 2),
    #             'cluster': cluster_status,
    #             'reachable_nodes': reachable_count,
    #             'total_nodes': total_count
    #         }
    #
    #     except Exception as e:
    #         return {
    #             'status': 'ERROR',
    #             'response_time': round(time.time() - start_time, 2),
    #             'error': str(e)
    #         }

    def run_check(self):
        """Execute MariaDB/Galera cluster health check"""
        start_time = time.time()

        try:
            # print(f"🔍 DEBUG MariaDB: Checking {len(self.nodes)} nodes")

            # 1. Check all nodes in parallel
            cluster_status = self._check_galera_cluster()

            # 2. Calculate reachable nodes count
            reachable_count = len(cluster_status['reachable_nodes'])
            total_count = len(self.nodes)

            # print(f"🔍 DEBUG MariaDB: {reachable_count}/{total_count} nodes reachable")
            # print(f"🔍 DEBUG Reachable: {cluster_status['reachable_nodes']}")
            # print(f"🔍 DEBUG Unreachable: {cluster_status['unreachable_nodes']}")

            # 3. Determine overall status
            if reachable_count == total_count:
                cluster_healthy = self._determine_cluster_status(cluster_status)
                # print(f"🔍 DEBUG Cluster healthy: {cluster_healthy}")
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

            # print(f"🔍 DEBUG Final status: {status}")
            return result

        except Exception as e:
            # print(f"🔍 DEBUG MariaDB exception: {e}")
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

        # 2. Execute parallel checks with ThreadPoolExecutor
        with ThreadPoolExecutor(max_workers=min(5, len(node_tasks))) as executor:
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
                    else:
                        status['unreachable_nodes'].append(display_name)

                except Exception:
                    status['unreachable_nodes'].append(display_name)

        return status

    def _check_single_node(self, display_name, connect_host):
        """Check health of single MariaDB node"""
        try:
            # print(f"🔍 DEBUG Connecting to {display_name} ({connect_host})")
            start_time = time.time()

            # 1. Establish database connection
            # connection = pymysql.connect(
            #     host=connect_host,
            #     **self.db_config,
            #     unix_socket=None
            # )

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

            # print(f"🔍 DEBUG {display_name}: connected successfully")
            return {
                'reachable': True,
                'response_time': round(response_time, 3),
                'metrics': metrics
            }

        except Exception as e:
            # print(f"🔍 DEBUG {display_name} failed: {e}")
            return {
                'reachable': False,
                'error': str(e)
            }

    # def _check_single_node(self, display_name, connect_host):
    #     """Check health of single MariaDB node and collect Galera metrics"""
    #     try:
    #         start_time = time.time()
    #
    #         # 1. Establish database connection
    #         connection = pymysql.connect(
    #             host=connect_host,
    #             **self.db_config
    #         )
    #
    #         # 2. Execute Galera status query
    #         with connection.cursor() as cursor:
    #             cursor.execute("""
    #                 SHOW GLOBAL STATUS WHERE Variable_name IN (
    #                     'wsrep_cluster_status',
    #                     'wsrep_cluster_size',
    #                     'wsrep_ready',
    #                     'wsrep_local_state_comment',
    #                     'wsrep_connected'
    #                 )
    #             """)
    #             results = cursor.fetchall()
    #
    #         response_time = time.time() - start_time
    #         connection.close()
    #
    #         # 3. Parse metrics into structured format
    #         metrics = self._parse_galera_metrics(results)
    #
    #         return {
    #             'reachable': True,
    #             'response_time': round(response_time, 3),
    #             'metrics': metrics
    #         }
    #
    #     except Exception as e:
    #         # Connection errors, timeouts, authentication failures
    #         return {
    #             'reachable': False,
    #             'error': str(e)
    #         }



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

        return {
            'cluster_status': metrics_dict.get('wsrep_cluster_status', 'Unknown'),
            'cluster_size': int(metrics_dict.get('wsrep_cluster_size', 0)),
            'node_ready': metrics_dict.get('wsrep_ready', 'OFF') == 'ON',
            'local_state': metrics_dict.get('wsrep_local_state_comment', 'Unknown'),
            'connected': metrics_dict.get('wsrep_connected', 'OFF') == 'ON'
        }

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
            return False

        # Check each reachable node for Galera health criteria
        healthy_nodes = 0
        expected_cluster_size = len(self.nodes)

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

        # Cluster is healthy if majority of nodes are healthy
        # (Galera requires quorum - typically majority of nodes)
        return healthy_nodes >= (expected_cluster_size // 2 + 1)