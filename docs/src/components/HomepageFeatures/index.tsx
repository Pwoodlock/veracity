import type {ReactNode} from 'react';
import clsx from 'clsx';
import Heading from '@theme/Heading';
import styles from './styles.module.css';

type FeatureItem = {
  title: string;
  Svg: React.ComponentType<React.ComponentProps<'svg'>>;
  description: ReactNode;
};

const FeatureList: FeatureItem[] = [
  {
    title: 'One-Click Installation',
    Svg: require('@site/static/img/undraw_docusaurus_mountain.svg').default,
    description: (
      <>
        Get up and running in minutes with our automated installer. One command installs
        Ruby, Rails, PostgreSQL, Redis, SaltStack, and Caddy with automatic HTTPS.
      </>
    ),
  },
  {
    title: 'SaltStack Integration',
    Svg: require('@site/static/img/undraw_docusaurus_tree.svg').default,
    description: (
      <>
        Powerful infrastructure automation with SaltStack 3007.8. Manage configurations,
        execute commands, and orchestrate deployments across your entire server fleet.
      </>
    ),
  },
  {
    title: 'Modern Rails Stack',
    Svg: require('@site/static/img/undraw_docusaurus_react.svg').default,
    description: (
      <>
        Built with Rails 8.1, Ruby 3.3.6 (via Mise), PostgreSQL, Redis, and Caddy.
        Push notifications via Gotify, vulnerability scanning, and API integrations included.
      </>
    ),
  },
];

function Feature({title, Svg, description}: FeatureItem) {
  return (
    <div className={clsx('col col--4')}>
      <div className="text--center">
        <Svg className={styles.featureSvg} role="img" />
      </div>
      <div className="text--center padding-horiz--md">
        <Heading as="h3">{title}</Heading>
        <p>{description}</p>
      </div>
    </div>
  );
}

export default function HomepageFeatures(): ReactNode {
  return (
    <section className={styles.features}>
      <div className="container">
        <div className="row">
          {FeatureList.map((props, idx) => (
            <Feature key={idx} {...props} />
          ))}
        </div>
      </div>
    </section>
  );
}
